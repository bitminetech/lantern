/*
 * ABI check for the test runner, ARM64 (AAPCS64). Test code: it is not part of the library.
 *
 * abi_call(ctx) calls ctx.fn with the 11 arguments in ctx, after it sets every
 * register the callee must keep to a known value and paints ctx.paint bytes
 * of stack below the call. It then records in ctx the status, a mask of the
 * kept state that changed, and the bytes of stack the call used.
 * The layout of ctx and the bits of the mask are in tests/runner/README.md.
 *
 * It makes no unwind entries for its own frame: it runs only inside the runner.
 */

.set ISA_ARM64, 1
.include "platform.inc"

FUNCTION abi_call
    UNWIND_END_PROLOGUE
    /* Save the caller's x19-x30 and d8-d15, and ctx at sp + 160. */
    sub     sp, sp, #176
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    stp     x25, x26, [sp, #48]
    stp     x27, x28, [sp, #64]
    stp     x29, x30, [sp, #80]
    stp     d8, d9, [sp, #96]
    stp     d10, d11, [sp, #112]
    stp     d12, d13, [sp, #128]
    stp     d14, d15, [sp, #144]
    str     x0, [sp, #160]
    /* Paint the stack below, from the top down, so each page is touched in order. */
    ldr     x9, [x0, #48]
    mov     x10, sp
    movz    x11, #0x5a5a
    movk    x11, #0x5a5a, lsl #16
    movk    x11, #0x5a5a, lsl #32
    movk    x11, #0x5a5a, lsl #48
1:  str     x11, [x10, #-8]!
    subs    x9, x9, #8
    b.ne    1b
    mov     x9, sp
    str     x9, [x0, #80]
    mrs     x9, fpcr
    str     x9, [x0, #88]
    /* x28 keeps ctx, x29 points at the saved x29 and x30, the others get known values. */
    mov     x28, x0
    add     x29, sp, #80
    movz    x19, #0x6978
    movk    x19, #0x4b5a, lsl #16
    movk    x19, #0x2d3c, lsl #32
    movk    x19, #0xf1e, lsl #48
    movz    x20, #0x6a79
    movk    x20, #0x4c5b, lsl #16
    movk    x20, #0x2e3d, lsl #32
    movk    x20, #0x101f, lsl #48
    movz    x21, #0x6b7a
    movk    x21, #0x4d5c, lsl #16
    movk    x21, #0x2f3e, lsl #32
    movk    x21, #0x1120, lsl #48
    movz    x22, #0x6c7b
    movk    x22, #0x4e5d, lsl #16
    movk    x22, #0x303f, lsl #32
    movk    x22, #0x1221, lsl #48
    movz    x23, #0x6d7c
    movk    x23, #0x4f5e, lsl #16
    movk    x23, #0x3140, lsl #32
    movk    x23, #0x1322, lsl #48
    movz    x24, #0x6e7d
    movk    x24, #0x505f, lsl #16
    movk    x24, #0x3241, lsl #32
    movk    x24, #0x1423, lsl #48
    movz    x25, #0x6f7e
    movk    x25, #0x5160, lsl #16
    movk    x25, #0x3342, lsl #32
    movk    x25, #0x1524, lsl #48
    movz    x26, #0x707f
    movk    x26, #0x5261, lsl #16
    movk    x26, #0x3443, lsl #32
    movk    x26, #0x1625, lsl #48
    movz    x27, #0x7180
    movk    x27, #0x5362, lsl #16
    movk    x27, #0x3544, lsl #32
    movk    x27, #0x1726, lsl #48
    movz    x9, #0x7988
    movk    x9, #0x5b6a, lsl #16
    movk    x9, #0x3d4c, lsl #32
    movk    x9, #0x1f2e, lsl #48
    fmov    d8, x9
    movz    x9, #0x7a89
    movk    x9, #0x5c6b, lsl #16
    movk    x9, #0x3e4d, lsl #32
    movk    x9, #0x202f, lsl #48
    fmov    d9, x9
    movz    x9, #0x7b8a
    movk    x9, #0x5d6c, lsl #16
    movk    x9, #0x3f4e, lsl #32
    movk    x9, #0x2130, lsl #48
    fmov    d10, x9
    movz    x9, #0x7c8b
    movk    x9, #0x5e6d, lsl #16
    movk    x9, #0x404f, lsl #32
    movk    x9, #0x2231, lsl #48
    fmov    d11, x9
    movz    x9, #0x7d8c
    movk    x9, #0x5f6e, lsl #16
    movk    x9, #0x4150, lsl #32
    movk    x9, #0x2332, lsl #48
    fmov    d12, x9
    movz    x9, #0x7e8d
    movk    x9, #0x606f, lsl #16
    movk    x9, #0x4251, lsl #32
    movk    x9, #0x2433, lsl #48
    fmov    d13, x9
    movz    x9, #0x7f8e
    movk    x9, #0x6170, lsl #16
    movk    x9, #0x4352, lsl #32
    movk    x9, #0x2534, lsl #48
    fmov    d14, x9
    movz    x9, #0x808f
    movk    x9, #0x6271, lsl #16
    movk    x9, #0x4453, lsl #32
    movk    x9, #0x2635, lsl #48
    fmov    d15, x9
    ldr     x16, [x28]
    ldp     x1, x2, [x28, #16]
    ldp     x3, x4, [x28, #32]
    ldr     x5, [x28, #112]
    ldp     x6, x7, [x28, #120]             /* arguments 7 and 8 in x6, x7; 9 to 12 on the stack */
    sub     sp, sp, #32
    ldp     x9, x10, [x28, #136]
    stp     x9, x10, [sp]
    ldp     x9, x10, [x28, #152]
    stp     x9, x10, [sp, #16]
    ldr     x0, [x28, #8]
    blr     x16
    add     sp, sp, #32
    mov     x9, #0
    movz    x10, #0x6978
    movk    x10, #0x4b5a, lsl #16
    movk    x10, #0x2d3c, lsl #32
    movk    x10, #0xf1e, lsl #48
    cmp     x19, x10
    cset    x11, ne
    orr     x9, x9, x11, lsl #0
    movz    x10, #0x6a79
    movk    x10, #0x4c5b, lsl #16
    movk    x10, #0x2e3d, lsl #32
    movk    x10, #0x101f, lsl #48
    cmp     x20, x10
    cset    x11, ne
    orr     x9, x9, x11, lsl #1
    movz    x10, #0x6b7a
    movk    x10, #0x4d5c, lsl #16
    movk    x10, #0x2f3e, lsl #32
    movk    x10, #0x1120, lsl #48
    cmp     x21, x10
    cset    x11, ne
    orr     x9, x9, x11, lsl #2
    movz    x10, #0x6c7b
    movk    x10, #0x4e5d, lsl #16
    movk    x10, #0x303f, lsl #32
    movk    x10, #0x1221, lsl #48
    cmp     x22, x10
    cset    x11, ne
    orr     x9, x9, x11, lsl #3
    movz    x10, #0x6d7c
    movk    x10, #0x4f5e, lsl #16
    movk    x10, #0x3140, lsl #32
    movk    x10, #0x1322, lsl #48
    cmp     x23, x10
    cset    x11, ne
    orr     x9, x9, x11, lsl #4
    movz    x10, #0x6e7d
    movk    x10, #0x505f, lsl #16
    movk    x10, #0x3241, lsl #32
    movk    x10, #0x1423, lsl #48
    cmp     x24, x10
    cset    x11, ne
    orr     x9, x9, x11, lsl #5
    movz    x10, #0x6f7e
    movk    x10, #0x5160, lsl #16
    movk    x10, #0x3342, lsl #32
    movk    x10, #0x1524, lsl #48
    cmp     x25, x10
    cset    x11, ne
    orr     x9, x9, x11, lsl #6
    movz    x10, #0x707f
    movk    x10, #0x5261, lsl #16
    movk    x10, #0x3443, lsl #32
    movk    x10, #0x1625, lsl #48
    cmp     x26, x10
    cset    x11, ne
    orr     x9, x9, x11, lsl #7
    movz    x10, #0x7180
    movk    x10, #0x5362, lsl #16
    movk    x10, #0x3544, lsl #32
    movk    x10, #0x1726, lsl #48
    cmp     x27, x10
    cset    x11, ne
    orr     x9, x9, x11, lsl #8
    /* Check sp, put it back, then check x28 against the copy of ctx on the stack. */
    mov     x10, x28
    ldr     x12, [x10, #80]
    mov     x13, sp
    cmp     x12, x13
    cset    x11, ne
    orr     x9, x9, x11, lsl #63
    mov     sp, x12
    ldr     x12, [sp, #160]
    cmp     x28, x12
    cset    x11, ne
    orr     x9, x9, x11, lsl #9
    add     x12, sp, #80
    cmp     x29, x12
    cset    x11, ne
    orr     x9, x9, x11, lsl #10
    movz    x12, #0x7988
    movk    x12, #0x5b6a, lsl #16
    movk    x12, #0x3d4c, lsl #32
    movk    x12, #0x1f2e, lsl #48
    fmov    x13, d8
    cmp     x13, x12
    cset    x11, ne
    orr     x9, x9, x11, lsl #11
    movz    x12, #0x7a89
    movk    x12, #0x5c6b, lsl #16
    movk    x12, #0x3e4d, lsl #32
    movk    x12, #0x202f, lsl #48
    fmov    x13, d9
    cmp     x13, x12
    cset    x11, ne
    orr     x9, x9, x11, lsl #12
    movz    x12, #0x7b8a
    movk    x12, #0x5d6c, lsl #16
    movk    x12, #0x3f4e, lsl #32
    movk    x12, #0x2130, lsl #48
    fmov    x13, d10
    cmp     x13, x12
    cset    x11, ne
    orr     x9, x9, x11, lsl #13
    movz    x12, #0x7c8b
    movk    x12, #0x5e6d, lsl #16
    movk    x12, #0x404f, lsl #32
    movk    x12, #0x2231, lsl #48
    fmov    x13, d11
    cmp     x13, x12
    cset    x11, ne
    orr     x9, x9, x11, lsl #14
    movz    x12, #0x7d8c
    movk    x12, #0x5f6e, lsl #16
    movk    x12, #0x4150, lsl #32
    movk    x12, #0x2332, lsl #48
    fmov    x13, d12
    cmp     x13, x12
    cset    x11, ne
    orr     x9, x9, x11, lsl #15
    movz    x12, #0x7e8d
    movk    x12, #0x606f, lsl #16
    movk    x12, #0x4251, lsl #32
    movk    x12, #0x2433, lsl #48
    fmov    x13, d13
    cmp     x13, x12
    cset    x11, ne
    orr     x9, x9, x11, lsl #16
    movz    x12, #0x7f8e
    movk    x12, #0x6170, lsl #16
    movk    x12, #0x4352, lsl #32
    movk    x12, #0x2534, lsl #48
    fmov    x13, d14
    cmp     x13, x12
    cset    x11, ne
    orr     x9, x9, x11, lsl #17
    movz    x12, #0x808f
    movk    x12, #0x6271, lsl #16
    movk    x12, #0x4453, lsl #32
    movk    x12, #0x2635, lsl #48
    fmov    x13, d15
    cmp     x13, x12
    cset    x11, ne
    orr     x9, x9, x11, lsl #18
    mrs     x12, fpcr
    ldr     x13, [x10, #88]
    cmp     x12, x13
    cset    x11, ne
    orr     x9, x9, x11, lsl #61
    msr     fpcr, x13
    str     x0, [x10, #56]
    /* The lowest painted word that changed gives the stack the call used. */
    ldr     x12, [x10, #48]
    mov     x13, sp
    sub     x12, x13, x12
    movz    x14, #0x5a5a
    movk    x14, #0x5a5a, lsl #16
    movk    x14, #0x5a5a, lsl #32
    movk    x14, #0x5a5a, lsl #48
2:  cmp     x12, x13
    b.hs    3f
    ldr     x15, [x12]
    cmp     x15, x14
    b.ne    3f
    add     x12, x12, #8
    b       2b
3:  sub     x12, x13, x12
    str     x12, [x10, #72]
    str     x9, [x10, #64]
    ldp     x19, x20, [sp, #0]
    ldp     x21, x22, [sp, #16]
    ldp     x23, x24, [sp, #32]
    ldp     x25, x26, [sp, #48]
    ldp     x27, x28, [sp, #64]
    ldp     x29, x30, [sp, #80]
    ldp     d8, d9, [sp, #96]
    ldp     d10, d11, [sp, #112]
    ldp     d12, d13, [sp, #128]
    ldp     d14, d15, [sp, #144]
    add     sp, sp, #176
    ret
END_FUNCTION abi_call
