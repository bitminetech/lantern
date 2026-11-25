/*
 * Copy and zero, x86-64: helpers that every object of the core includes.
 */

/* dst rdi, src rsi, n rdx: forward, so a copy to a lower, overlapping place is right. */
LOCAL_FUNCTION lantern_copy
    UNWIND_END_PROLOGUE
    mov     %rdx, %rcx
    rep movsb
    RETURN_OK
END_FUNCTION lantern_copy

LOCAL_FUNCTION lantern_zero
    UNWIND_END_PROLOGUE
    mov     %rsi, %rcx
    xor     %eax, %eax
    rep stosb
    ret
END_FUNCTION lantern_zero
