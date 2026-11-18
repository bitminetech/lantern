/*
 * The shell of the lantern binary for Linux on ARM64: memory, files, the log and the clock,
 * through direct system calls. Requirements: docs/reference/shell.md.
 *
 * System calls: the number in x8, arguments in x0 to x5, "svc #0"; x0 holds the result, or minus
 * the error number (-4095 to -1); the other registers keep their values.
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

/* Linux numbers: include/uapi/asm-generic/unistd.h and the uapi headers. */
.set SYS_OPENAT, 56
.set SYS_CLOSE, 57
.set SYS_READ, 63
.set SYS_WRITE, 64
.set SYS_FSTAT, 80
.set SYS_CLOCK_GETTIME, 113
.set SYS_MUNMAP, 215
.set SYS_MMAP, 222
.set OS_AT_FDCWD, -100
.set OS_O_RDONLY_CLOEXEC, 0x80000           /* O_RDONLY | O_CLOEXEC */
.set OS_PROT_RW, 3                          /* PROT_READ | PROT_WRITE */
.set OS_MAP_PRIVATE_ANON, 0x22              /* MAP_PRIVATE | MAP_ANONYMOUS */
.set OS_EINTR, 4
.set OS_ENAMETOOLONG, 36
.set OS_CLOCK_REALTIME, 0
.set OS_STAT_SIZE, 48                       /* st_size in the generic struct stat */
.set SHELL_PATH_MAX, 4095
.set SHELL_READ_FRAME, 2 << 12              /* read_file: 64 the struct stat, 256 the path */

.macro SYSCALL number
    mov     x8, #\number
    svc     #0
.endm

/* To label when \reg is minus an error number (-4095 to -1). */
.macro IF_ERROR reg, label
    cmn     \reg, #4095
    b.hs    \label
.endm

/* (size, out): docs/reference/shell.md. */
FUNCTION lantern_shell_map
    UNWIND_END_PROLOGUE
    mov     x9, x1
    ldr     x1, [x0]
    mov     x0, #0
    mov     x2, #OS_PROT_RW
    mov     x3, #OS_MAP_PRIVATE_ANON
    mov     x4, #-1
    mov     x5, #0
    SYSCALL SYS_MMAP
    cmn     x0, #4095                       /* no memory: 0 */
    csel    x0, xzr, x0, hs
    str     x0, [x9]
    mov     x0, #LANTERN_OK
    ret
END_FUNCTION lantern_shell_map

/* (address, size): docs/reference/shell.md. */
FUNCTION lantern_shell_unmap
    UNWIND_END_PROLOGUE
    ldr     x1, [x1]
    ldr     x0, [x0]
    SYSCALL SYS_MUNMAP
    mov     x0, #LANTERN_OK
    ret
END_FUNCTION lantern_shell_unmap

/*
 * (path, result): docs/reference/shell.md. x9 result, x10 the file, x11 the memory, x12 the
 * file's size, x13 the size mapped, x14 the bytes read or an error. Frame: 64 a struct stat,
 * 256 the path with a zero after it.
 */
FUNCTION lantern_shell_read_file
    sub     sp, sp, #SHELL_READ_FRAME
    UNWIND_ALLOC (SHELL_READ_FRAME)
    UNWIND_END_PROLOGUE
    mov     x9, x1
    stp     xzr, xzr, [x9]
    stp     xzr, xzr, [x9, #16]
    ldr     x2, [x0, #16]                   /* the path, with a zero after it */
    cmp     x2, #SHELL_PATH_MAX
    b.hi    91f
    ldr     x1, [x0, #8]
    add     x1, x0, x1
    add     x3, sp, #256
    mov     x4, #0
1:  cmp     x4, x2
    b.hs    2f
    ldrb    w5, [x1, x4]
    strb    w5, [x3, x4]
    add     x4, x4, #1
    b       1b
2:  strb    wzr, [x3, x4]
    mov     x0, #OS_AT_FDCWD
    mov     x1, x3
    mov     x2, #OS_O_RDONLY_CLOEXEC
    mov     x3, #0
    SYSCALL SYS_OPENAT
    IF_ERROR x0, 90f
    mov     x10, x0
    add     x1, sp, #64                     /* its size */
    SYSCALL SYS_FSTAT
    IF_ERROR x0, 80f
    ldr     x12, [sp, #(64 + OS_STAT_SIZE)]
    mov     x13, x12                        /* memory of the size, at least 1 byte */
    cbnz    x13, 3f
    mov     x13, #1
3:  mov     x0, #0
    mov     x1, x13
    mov     x2, #OS_PROT_RW
    mov     x3, #OS_MAP_PRIVATE_ANON
    mov     x4, #-1
    mov     x5, #0
    SYSCALL SYS_MMAP
    IF_ERROR x0, 80f
    mov     x11, x0
    mov     x14, #0
4:  cmp     x14, x12                        /* every byte */
    b.hs    5f
    mov     x0, x10
    add     x1, x11, x14
    sub     x2, x12, x14
    SYSCALL SYS_READ
    cmn     x0, #OS_EINTR
    b.eq    4b
    IF_ERROR x0, 70f
    cbz     x0, 71f
    add     x14, x14, x0
    b       4b
5:  mov     x0, x10
    SYSCALL SYS_CLOSE
    stp     xzr, x11, [x9]
    stp     x12, x13, [x9, #16]
    b       99f
71: mov     x0, #-1                         /* the file ends before its size: error 1 */
70: mov     x14, x0                         /* the memory goes back */
    mov     x0, x11
    mov     x1, x13
    SYSCALL SYS_MUNMAP
    mov     x0, x14
80: mov     x14, x0                         /* the file closes */
    mov     x0, x10
    SYSCALL SYS_CLOSE
    mov     x0, x14
90: neg     x0, x0                          /* the error */
    str     x0, [x9]
    b       99f
91: mov     x0, #-OS_ENAMETOOLONG
    b       90b
99: mov     x0, #LANTERN_OK
    UNWIND_BEGIN_EPILOGUE
    add     sp, sp, #SHELL_READ_FRAME
    UNWIND_FREE (SHELL_READ_FRAME)
    UNWIND_END_EPILOGUE
    ret
END_FUNCTION lantern_shell_read_file

/* (stream, bytes): docs/reference/shell.md. x9 the file, x10 the next byte, x11 the bytes left. */
FUNCTION lantern_shell_write
    UNWIND_END_PROLOGUE
    ldr     x9, [x0]
    ldr     x10, [x1, #8]
    add     x10, x1, x10
    ldr     x11, [x1, #16]
1:  cbz     x11, 9f
    mov     x0, x9
    mov     x1, x10
    mov     x2, x11
    SYSCALL SYS_WRITE
    cmn     x0, #OS_EINTR
    b.eq    1b
    IF_ERROR x0, 9f
    add     x10, x10, x0
    sub     x11, x11, x0
    b       1b
9:  mov     x0, #LANTERN_OK
    ret
END_FUNCTION lantern_shell_write

/* (out): docs/reference/shell.md. Frame: a struct timespec. */
FUNCTION lantern_shell_time_ms
    sub     sp, sp, #16
    UNWIND_ALLOC 16
    UNWIND_END_PROLOGUE
    mov     x9, x0
    mov     x0, #OS_CLOCK_REALTIME
    mov     x1, sp
    SYSCALL SYS_CLOCK_GETTIME
    ldp     x10, x11, [sp]                  /* seconds * 1000 + nanoseconds / 10^6 */
    mov     x12, #1000
    mul     x10, x10, x12
    MOVQ    x12, 1000000
    udiv    x11, x11, x12
    add     x10, x10, x11
    str     x10, [x9]
    mov     x0, #LANTERN_OK
    UNWIND_BEGIN_EPILOGUE
    add     sp, sp, #16
    UNWIND_FREE 16
    UNWIND_END_EPILOGUE
    ret
END_FUNCTION lantern_shell_time_ms
