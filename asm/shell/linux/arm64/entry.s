/*
 * The entry point of the lantern binary for Linux on ARM64: the arguments, without the program
 * name, as an ArgList; then lantern_app_main; then exit_group with its status.
 * Requirements: docs/reference/shell.md, _start. At _start, sp holds argc, then argv,
 * a 0, envp, a 0, then the auxiliary vector. x19 the argument count, x20 argv, x21 the argument
 * bytes, x22 the ArgList's size, x23 the ArgList, x24 the next byte, x25 1 when the CPU has
 * FEAT_SHA256 (shell.md, The sha variant).
 */
.set ISA_ARM64, 1
.include "ssz.inc"
.include "crypto.inc"
.include "bls12381.inc"
.include "kzg.inc"
.include "preset.inc"
.include "lantern.inc"
.include "platform.inc"

.set SYS_EXIT_GROUP, 94

    .text
    .globl _start
    .p2align 4
_start:
    mov     x29, #0
    mov     x30, #0
    ldr     x9, [sp]                        /* the sha variant: bit 6 (HWCAP_SHA2) of AT_HWCAP */
    add     x10, sp, #16
    add     x10, x10, x9, lsl #3            /* envp */
70: ldr     x11, [x10], #8
    cbnz    x11, 70b
    mov     x25, #0
71: ldp     x11, x12, [x10], #16            /* the auxiliary vector: type, value; AT_NULL ends it */
    cbz     x11, 72f
    cmp     x11, #16                        /* AT_HWCAP */
    b.ne    71b
    ubfx    x25, x12, #6, #1
72: ldr     x19, [sp]
    add     x20, sp, #16                    /* argv[1] */
    sub     x19, x19, #1
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
    sub     sp, sp, #16
    str     x22, [sp]
    mov     x0, sp
    add     x1, sp, #8
    bl      lantern_shell_map
    ldr     x23, [sp, #8]
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
6:  mov     x0, x23
    cbz     x25, 60f
    bl      lx_lantern_app_main
    b       8f
60: bl      lantern_app_main
    b       8f
9:  mov     x0, #2                          /* no memory for the arguments */
8:  mov     x8, #SYS_EXIT_GROUP
    svc     #0
