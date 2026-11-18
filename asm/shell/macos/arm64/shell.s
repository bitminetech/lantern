/*
 * The shell of the lantern binary for macOS on ARM64: memory, files, the log and the clock,
 * through libSystem. Requirements: docs/reference/shell.md.
 *
 * The functions use AAPCS64 and call libSystem with the same convention. A libSystem call that
 * fails gives -1, with the error number in errno (from __error()).
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

/* libSystem numbers: the macOS SDK headers. */
.set OS_PROT_RW, 3                          /* PROT_READ | PROT_WRITE, sys/mman.h */
.set OS_MAP_PRIVATE_ANON, 0x1002            /* MAP_PRIVATE | MAP_ANON, sys/mman.h */
.set OS_O_RDONLY_CLOEXEC, 0x1000000         /* O_RDONLY | O_CLOEXEC, sys/fcntl.h */
.set OS_SEEK_SET, 0                         /* sys/_types/_seek_set.h */
.set OS_SEEK_END, 2
.set OS_EINTR, 4                            /* sys/errno.h */
.set OS_ENAMETOOLONG, 63
.set OS_CLOCK_REALTIME, 0                   /* _time.h */
.set SHELL_PATH_MAX, 4095
.set SHELL_READ_FRAME, 4096                 /* read_file: the path with a zero after it */

/* x0 = errno, after a libSystem call that gave -1. */
.macro OS_ERRNO
    CALL_GLOBAL __error
    ldrsw   x0, [x0]
.endm

/* (size, out): docs/reference/shell.md. x19 out. */
FUNCTION lantern_shell_map
    ENTER 0
    mov     x19, x1
    ldr     x1, [x0]
    mov     x0, #0
    mov     w2, #OS_PROT_RW
    mov     w3, #OS_MAP_PRIVATE_ANON
    mov     w4, #-1
    mov     x5, #0
    CALL_GLOBAL mmap
    cmn     x0, #1                          /* MAP_FAILED: 0 */
    csel    x0, xzr, x0, eq
    str     x0, [x19]
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_map

/* (address, size): docs/reference/shell.md. */
FUNCTION lantern_shell_unmap
    ENTER 0
    ldr     x1, [x1]
    ldr     x0, [x0]
    CALL_GLOBAL munmap
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_unmap

/*
 * (path, result): docs/reference/shell.md. x19 result, x20 the file, x21 the memory, x22 the
 * file's size, x23 the size mapped (24 more), x24 the bytes read or an error. Frame: the path
 * with a zero after it, at sp.
 */
FUNCTION lantern_shell_read_file
    ENTER 0
    sub     sp, sp, #SHELL_READ_FRAME
    mov     x19, x1
    stp     xzr, xzr, [x19]
    stp     xzr, xzr, [x19, #16]
    ldr     x2, [x0, #16]                   /* the path, with a zero after it */
    cmp     x2, #SHELL_PATH_MAX
    b.hi    91f
    ldr     x1, [x0, #8]
    add     x1, x0, x1
    mov     x3, sp
    mov     x4, #0
1:  cmp     x4, x2
    b.hs    2f
    ldrb    w5, [x1, x4]
    strb    w5, [x3, x4]
    add     x4, x4, #1
    b       1b
2:  strb    wzr, [x3, x4]
    mov     x0, sp
    MOVQ    x1, OS_O_RDONLY_CLOEXEC
    CALL_GLOBAL open
    cmn     w0, #1
    b.eq    90f
    mov     w20, w0
    mov     w0, w20                         /* its size: the end's offset, then back to the start */
    mov     x1, #0
    mov     w2, #OS_SEEK_END
    CALL_GLOBAL lseek
    cmn     x0, #1
    b.eq    80f
    mov     x22, x0
    mov     w0, w20
    mov     x1, #0
    mov     w2, #OS_SEEK_SET
    CALL_GLOBAL lseek
    cmn     x0, #1
    b.eq    80f
    add     x23, x22, #24                   /* a ByteList: 24 bytes, then the file's */
    mov     x0, #0
    mov     x1, x23
    mov     w2, #OS_PROT_RW
    mov     w3, #OS_MAP_PRIVATE_ANON
    mov     w4, #-1
    mov     x5, #0
    CALL_GLOBAL mmap
    cmn     x0, #1
    b.eq    80f
    mov     x21, x0
    mov     x2, #24
    stp     x23, x2, [x21]
    str     x22, [x21, #16]
    mov     x24, #0
4:  cmp     x24, x22                        /* every byte */
    b.hs    5f
    mov     w0, w20
    add     x1, x21, x24
    add     x1, x1, #24
    sub     x2, x22, x24
    CALL_GLOBAL read
    cmn     x0, #1
    b.ne    41f
    OS_ERRNO
    cmp     x0, #OS_EINTR
    b.eq    4b
    b       70f
41: cbz     x0, 71f
    add     x24, x24, x0
    b       4b
5:  mov     w0, w20
    CALL_GLOBAL close
    stp     xzr, x21, [x19]
    stp     x22, x23, [x19, #16]
    b       99f
71: mov     x0, #1                          /* the file ends before its size: error 1 */
70: mov     x24, x0                         /* the memory goes back */
    mov     x0, x21
    mov     x1, x23
    CALL_GLOBAL munmap
    mov     x0, x24
    b       81f
80: OS_ERRNO                                /* the file closes */
81: mov     x24, x0
    mov     w0, w20
    CALL_GLOBAL close
    mov     x0, x24
    b       92f
90: OS_ERRNO
92: str     x0, [x19]                       /* the error */
    b       99f
91: mov     x0, #OS_ENAMETOOLONG
    b       92b
99: add     sp, sp, #SHELL_READ_FRAME
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_read_file

/* (stream, bytes): docs/reference/shell.md. x19 the file, x20 the next byte, x21 the bytes left. */
FUNCTION lantern_shell_write
    ENTER 0
    ldr     x19, [x0]
    ldr     x20, [x1, #8]
    add     x20, x1, x20
    ldr     x21, [x1, #16]
1:  cbz     x21, 9f
    mov     w0, w19
    mov     x1, x20
    mov     x2, x21
    CALL_GLOBAL write
    cmn     x0, #1
    b.ne    2f
    OS_ERRNO
    cmp     x0, #OS_EINTR
    b.eq    1b
    b       9f
2:  add     x20, x20, x0
    sub     x21, x21, x0
    b       1b
9:  mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_write

/* (out): docs/reference/shell.md. x19 out. */
FUNCTION lantern_shell_time_ms
    ENTER 0
    mov     x19, x0
    mov     w0, #OS_CLOCK_REALTIME
    CALL_GLOBAL clock_gettime_nsec_np
    MOVQ    x1, 1000000
    udiv    x0, x0, x1
    str     x0, [x19]
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_time_ms
