/*
 * Copy and zero, ARM64: helpers that every object of the core includes.
 */

LOCAL_FUNCTION lantern_copy
    UNWIND_END_PROLOGUE
    cmp     x2, #64
    b.lo    2f
1:  ldp     q0, q1, [x1]
    ldp     q2, q3, [x1, #32]
    add     x1, x1, #64
    stp     q0, q1, [x0]
    stp     q2, q3, [x0, #32]
    add     x0, x0, #64
    sub     x2, x2, #64
    cmp     x2, #64
    b.hs    1b
2:  cbz     x2, 4f
3:  ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    subs    x2, x2, #1
    b.ne    3b
4:  ret
END_FUNCTION lantern_copy

LOCAL_FUNCTION lantern_zero
    UNWIND_END_PROLOGUE
    cmp     x1, #16
    b.lo    2f
1:  stp     xzr, xzr, [x0], #16
    sub     x1, x1, #16
    cmp     x1, #16
    b.hs    1b
2:  cbz     x1, 4f
3:  strb    wzr, [x0], #1
    subs    x1, x1, #1
    b.ne    3b
4:  ret
END_FUNCTION lantern_zero
