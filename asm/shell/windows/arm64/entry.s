/*
 * The entry point of the lantern binary for Windows on ARM64: mainCRTStartup; the command line
 * of GetCommandLineW split by CommandLineToArgvW, without the program name, each argument in
 * UTF-8, as an ArgList; then lantern_app_main; then ExitProcess with its status.
 * Requirements: docs/reference/shell.md, mainCRTStartup. x19 the argument count, x20 the wide
 * arguments, x21 the UTF-8 bytes, x22 the ArgList's size, x23 the ArgList, x24 an argument's
 * number, x25 the next byte, x26 an Arg entry. Locals: L argc, L+8 the size, L+16 the address.
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

.set OS_CP_UTF8, 65001                      /* winnls.h */

FUNCTION mainCRTStartup
    ENTER 32
    CALL_GLOBAL GetCommandLineW
    add     x1, sp, #L
    CALL_GLOBAL CommandLineToArgvW
    cbz     x0, 9f
    mov     x20, x0
    ldrsw   x19, [sp, #L]                   /* without the program name */
    subs    x19, x19, #1
    csel    x19, xzr, x19, lt
    mov     x21, #0                         /* the UTF-8 bytes of every argument */
    mov     x24, #0
1:  cmp     x24, x19
    b.hs    3f
    mov     w0, #OS_CP_UTF8
    mov     w1, #0
    add     x9, x20, #8
    ldr     x2, [x9, x24, lsl #3]
    mov     w3, #-1
    mov     x4, #0
    mov     w5, #0
    mov     x6, #0
    mov     x7, #0
    CALL_GLOBAL WideCharToMultiByte
    mov     w0, w0                          /* its bytes, and a zero */
    cbz     x0, 2f
    sub     x0, x0, #1
2:  add     x21, x21, x0
    add     x24, x24, #1
    b       1b
3:  lsl     x22, x19, #4                    /* the ArgList: 40 bytes, the Arg entries, the bytes, room for a zero */
    add     x22, x22, x21
    add     x22, x22, #(40 + 8)
    and     x22, x22, #~7
    str     x22, [sp, #(L + 8)]
    add     x0, sp, #(L + 8)
    add     x1, sp, #(L + 16)
    CALL_GLOBAL lantern_shell_map
    ldr     x23, [sp, #(L + 16)]
    cbz     x23, 9f
    str     x22, [x23]
    mov     x9, #40
    stp     x9, x19, [x23, #8]
    lsl     x25, x19, #4
    add     x25, x25, #40
    stp     x25, x21, [x23, #24]
    mov     x24, #0
4:  cmp     x24, x19
    b.hs    6f
    add     x26, x23, x24, lsl #4
    str     x25, [x26, #40]
    mov     w0, #OS_CP_UTF8
    mov     w1, #0
    add     x9, x20, #8
    ldr     x2, [x9, x24, lsl #3]
    mov     w3, #-1
    add     x4, x23, x25
    sub     x5, x22, x25
    mov     x6, #0
    mov     x7, #0
    CALL_GLOBAL WideCharToMultiByte
    mov     w0, w0
    cbz     x0, 5f
    sub     x0, x0, #1
5:  str     x0, [x26, #48]
    add     x25, x25, x0
    add     x24, x24, #1
    b       4b
6:  mov     x0, x20
    CALL_GLOBAL LocalFree
    mov     w0, #30                         /* the sha variant: PF_ARM_V8_CRYPTO_INSTRUCTIONS_AVAILABLE */
    CALL_GLOBAL IsProcessorFeaturePresent
    cbz     w0, 60f
    mov     x0, x23
    CALL_GLOBAL lx_lantern_app_main
    CALL_GLOBAL ExitProcess
60: mov     x0, x23
    CALL_GLOBAL lantern_app_main
    CALL_GLOBAL ExitProcess
9:  mov     w0, #2                          /* no memory for the arguments */
    CALL_GLOBAL ExitProcess
END_FUNCTION mainCRTStartup
