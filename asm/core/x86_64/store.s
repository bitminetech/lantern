/*
 * The fork choice Store's own functions, x86-64: they read no fork's layouts.
 * Requirements: docs/reference/fork-choice.md.
 */

LEAF lantern_store_size
    mov     (%rdi), %rax                    # nodes
    mov     $BlockNode__mem, %ecx
    mul     %rcx
    jc      9f
    mov     8(%rdi), %rcx                   # validators * StoreValidator__mem fits
    mov     %rcx, %rdx
    shr     $59, %rdx
    jnz     9f
    shl     $5, %rcx
    add     %rcx, %rax
    jc      9f
    add     $STORE_FIXED, %rax
    jc      9f
    mov     %rax, (%rsi)
    RETURN_OK
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
END_FUNCTION lantern_store_size

/* rbx store, rbp room, r12 out, r13 node capacity, r14 validator capacity, r15 old validator count. Locals: L size. */
FUNCTION lantern_store_copy
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rbp), %r13
    mov     8(%rbp), %r14
    cmp     (Store_blocks + 8)(%rbx), %r13
    jb      9f
    mov     (Store_validators + 8)(%rbx), %r15
    cmp     %r15, %r14
    jb      9f
    mov     %rbp, %rdi
    lea     L(%rsp), %rsi
    call    lantern_store_size
    test    %rax, %rax
    jnz     9f
    mov     L(%rsp), %rax
    cmp     %rax, (%r12)
    jb      9f
    lea     8(%r12), %rdi                   # the fixed fields after size
    lea     8(%rbx), %rsi
    mov     $(STORE_FIXED - 8), %edx
    call    lantern_copy
    movq    $STORE_FIXED, Store_blocks(%r12)        # the parts at their new capacities
    imul    $BlockNode__mem, %r13, %rax
    add     $STORE_FIXED, %rax
    mov     %rax, Store_validators(%r12)
    mov     %r14, (Store_validators + 8)(%r12)
    lea     STORE_FIXED(%r12), %rdi
    PART    %rsi, %rdx, %rbx, Store_blocks
    imul    $BlockNode__mem, %rdx, %rdx
    call    lantern_copy
    mov     Store_validators(%r12), %rdi
    add     %r12, %rdi
    PART    %rsi, %rdx, %rbx, Store_validators
    shl     $5, %rdx
    call    lantern_copy
    mov     Store_validators(%r12), %rax    # the new entries: no latest message, balance or flags
    add     %r12, %rax
    mov     %r15, %rcx
    shl     $5, %rcx
    add     %rcx, %rax
    mov     %r14, %rcx
    sub     %r15, %rcx
1:  test    %rcx, %rcx
    jz      2f
    movq    $0, (%rax)
    movq    $-1, 8(%rax)
    movq    $0, 16(%rax)
    movq    $0, 24(%rax)
    add     $StoreValidator__mem, %rax
    dec     %rcx
    jmp     1b
2:  xor     %eax, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
END_FUNCTION lantern_store_copy

/*
 * Optimistic sync: rdi store, rsi node, rdx payload_status, rcx result. rsi node index,
 * r8 node count, r9 nodes, rax the node.
 */
LEAF lantern_store_payload_status
    movq    $0, (%rcx)
    mov     (%rsi), %rsi
    mov     (%rdx), %rdx
    mov     (Store_blocks + 8)(%rdi), %r8
    cmp     %r8, %rsi
    jae     8f
    mov     Store_blocks(%rdi), %r9
    add     %rdi, %r9
    imul    $BlockNode__mem, %rsi, %rax
    add     %r9, %rax
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, BlockNode_payload_status(%rax)
    jne     6f                              # only NOT_VALIDATED blocks change
    test    %rdx, %rdx
    jz      3f
    cmp     $PAYLOAD_STATUS_INVALIDATED, %rdx
    jne     6f
    movq    $PAYLOAD_STATUS_INVALIDATED, BlockNode_payload_status(%rax)    # the block and its descendants
    inc     %rsi
1:  cmp     %r8, %rsi
    jae     6f
    imul    $BlockNode__mem, %rsi, %rax
    add     %r9, %rax
    mov     BlockNode_parent(%rax), %rdx
    cmp     $-1, %rdx
    je      2f
    imul    $BlockNode__mem, %rdx, %rdx
    cmpq    $PAYLOAD_STATUS_INVALIDATED, BlockNode_payload_status(%r9,%rdx)
    jne     2f
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, BlockNode_payload_status(%rax)
    jne     2f
    movq    $PAYLOAD_STATUS_INVALIDATED, BlockNode_payload_status(%rax)
2:  inc     %rsi
    jmp     1b
3:  movq    $PAYLOAD_STATUS_VALID, BlockNode_payload_status(%rax)  # VALID: the block and its NOT_VALIDATED ancestors
    mov     BlockNode_parent(%rax), %rsi
    cmp     $-1, %rsi
    je      6f
    imul    $BlockNode__mem, %rsi, %rax
    add     %r9, %rax
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, BlockNode_payload_status(%rax)
    je      3b
6:  xor     %eax, %eax
    ret
8:  movq    $LANTERN_INVALID_UNKNOWN_BLOCK, (%rcx)
    xor     %eax, %eax
    ret
END_FUNCTION lantern_store_payload_status
