/*
 * The entry point of the lantern binary for macOS on ARM64: main, which libSystem calls with argc
 * and argv; the arguments, without the program name, as an ArgList; then lantern_app_main, whose
 * status main returns as the exit code. Requirements: docs/reference/shell.md, main.
 * x19 the argument count, x20 argv, x21 the argument bytes, x22 the ArgList's size, x23 the
 * ArgList, x24 the next byte. Locals: L the size, L+8 the address.
 */
.set ISA_ARM64, 1
.include "ssz.inc"
.include "crypto.inc"
.include "bls12381.inc"
.include "kzg.inc"
.include "preset.inc"
.include "lantern.inc"
.include "platform.inc"
.include "macros.s"

/* (argc, argv) -> the exit code. */
FUNCTION main
    ENTER 16
    subs    x19, x0, #1                     /* without the program name */
    csel    x19, xzr, x19, lo
    add     x20, x1, #8                     /* argv[1] */
    mov     x21, #0                         /* the bytes of every argument */
    mov     x9, #0
1:  cmp     x9, x19
    b.hs    3f
    ldr     x10, [x20, x9, lsl #3]
    mov     x11, #0
2:  ldrb    w12, [x10, x11]
    cbz     w12, 21f
    add     x11, x11, #1
    b       2b
21: add     x21, x21, x11
    add     x9, x9, #1
    b       1b
3:  lsl     x22, x19, #4                    /* the ArgList: 40 bytes, the Arg entries, the bytes */
    add     x22, x22, x21
    add     x22, x22, #(40 + 7)
    and     x22, x22, #~7
    str     x22, [sp, #L]
    add     x0, sp, #L
    add     x1, sp, #(L + 8)
    CALL_GLOBAL lantern_shell_map
    ldr     x23, [sp, #(L + 8)]
    cbz     x23, 9f
    str     x22, [x23]
    mov     x9, #40
    stp     x9, x19, [x23, #8]
    lsl     x24, x19, #4
    add     x24, x24, #40
    stp     x24, x21, [x23, #24]
    mov     x9, #0
4:  cmp     x9, x19
    b.hs    6f
    ldr     x10, [x20, x9, lsl #3]
    add     x11, x23, x9, lsl #4
    str     x24, [x11, #40]
    mov     x12, #0
5:  ldrb    w13, [x10, x12]
    cbz     w13, 51f
    strb    w13, [x23, x24]
    add     x24, x24, #1
    add     x12, x12, #1
    b       5b
51: str     x12, [x11, #48]
    add     x9, x9, #1
    b       4b
6:  ADDRESS x0, entry_sha_feature        /* the sha variant (shell.md, The sha variant): sysctlbyname */
    add     x1, sp, #L
    str     wzr, [x1]
    add     x2, sp, #(L + 8)
    mov     x9, #4
    str     x9, [x2]
    mov     x3, #0
    mov     x4, #0
    CALL_GLOBAL sysctlbyname
    cbnz    w0, 60f
    ldr     w9, [sp, #L]
    cmp     w9, #1
    b.ne    60f
    mov     x0, x23
    CALL_GLOBAL lx_lantern_app_main
    LEAVE 16
60: mov     x0, x23
    CALL_GLOBAL lantern_app_main
    LEAVE 16
9:  mov     x0, #2                          /* no memory for the arguments */
    LEAVE 16
END_FUNCTION main

    RODATA
entry_sha_feature:
    .asciz  "hw.optional.arm.FEAT_SHA256"
