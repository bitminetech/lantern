/*
 * Finding a block of Seen, x86-64: an L0 helper of the common object and of each fork's object.
 * Requirements: docs/reference/networking.md.
 */

/* L0: rax = the SeenBlock of root rsi in seen rdi, or 0. A leaf; uses rcx, rdx, xmm0-xmm2, r11. */
LOCAL_FUNCTION seen_find_block
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
END_FUNCTION seen_find_block
