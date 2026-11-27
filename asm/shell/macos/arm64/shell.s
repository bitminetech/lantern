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
.set OS_O_APPEND_CREATE, 0x1000209         /* O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, sys/fcntl.h */
.set OS_O_RDWR_CREATE, 0x1000202           /* O_RDWR | O_CREAT | O_CLOEXEC, sys/fcntl.h */
.set OS_F_FULLFSYNC, 51                     /* sys/fcntl.h */
.set OS_PROT_READ, 1                        /* sys/mman.h */
.set OS_MAP_SHARED, 1
.set OS_EIO, 5                              /* sys/errno.h */
.set OS_EINVAL, 22
.set OS_MODE_FILE, 420                      /* 0644 */
.set OS_MODE_DIR, 493                       /* 0755 */
.set SHELL_WRITE_MAX, 1 << 30               /* write refuses more than INT_MAX bytes */
.set SHELL_OPEN_FRAME, 4112                 /* open: 0 the variadic mode, 16 the path */
.set SHELL_TWO_PATHS, 8192                  /* rename: 0 from, 4096 to */

/* x0 = errno, after a libSystem call that gave -1. */
.macro OS_ERRNO
    CALL_GLOBAL __error
    ldrsw   x0, [x0]
.endm

/* A frame of size bytes below the saved registers; its release. Use x9. */
.macro SHELL_FRAME size
    MOVQ    x9, \size
    sub     sp, sp, x9
.endm

.macro SHELL_UNFRAME size
    MOVQ    x9, \size
    add     sp, sp, x9
.endm

/* The path ByteList at \src as a string with a zero after it at \dst; to \long when above SHELL_PATH_MAX bytes. Uses x2-x5. */
.macro CPATH src, dst, long
    ldr     x2, [\src, #16]
    cmp     x2, #SHELL_PATH_MAX
    b.hi    \long
    ldr     x3, [\src, #8]
    add     x3, \src, x3
    mov     x4, #0
88: cmp     x4, x2
    b.hs    89f
    ldrb    w5, [x3, x4]
    strb    w5, [\dst, x4]
    add     x4, x4, #1
    b       88b
89: strb    wzr, [\dst, x4]
.endm

/* After a libSystem call that gives -1 on an error: on to \ok when w0 is not -1; again at \again on EINTR; else x0 = errno. */
.macro OS_CHECK ok, again
    cmn     w0, #1
    b.ne    \ok
    OS_ERRNO
    cmp     x0, #OS_EINTR
    b.eq    \again
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

/* (path, mode, result): docs/reference/shell.md. x19 result, x20 the flags. Frame: 0 the variadic mode, 16 the path. */
FUNCTION lantern_shell_open
    ENTER 0
    SHELL_FRAME SHELL_OPEN_FRAME
    mov     x19, x2
    stp     xzr, xzr, [x19]
    ldr     x10, [x1]
    cmp     x10, #2
    b.hi    92f
    MOVQ    x11, OS_O_RDONLY_CLOEXEC
    MOVQ    x12, OS_O_APPEND_CREATE
    cmp     x10, #1
    csel    x11, x12, x11, eq
    MOVQ    x12, OS_O_RDWR_CREATE
    cmp     x10, #2
    csel    x20, x12, x11, eq
    add     x6, sp, #16
    CPATH   x0, x6, 91f
    mov     x0, #OS_MODE_FILE               /* open is variadic: the mode on the stack */
    str     x0, [sp]
1:  add     x0, sp, #16
    mov     x1, x20
    CALL_GLOBAL open
    OS_CHECK 2f, 1b
    b       90f
2:  mov     w0, w0
    str     x0, [x19, #8]
    b       99f
92: mov     x0, #OS_EINVAL
    b       90f
91: mov     x0, #OS_ENAMETOOLONG
90: str     x0, [x19]
99: SHELL_UNFRAME SHELL_OPEN_FRAME
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_open

/* (file, bytes, result): docs/reference/shell.md. x19 result, x20 the file, x21 the bytes, x22 their count, x23 written. */
FUNCTION lantern_shell_append
    ENTER 0
    mov     x19, x2
    stp     xzr, xzr, [x19]
    ldr     x20, [x0]
    ldr     x21, [x1, #8]
    add     x21, x1, x21
    ldr     x22, [x1, #16]
    mov     x23, #0
1:  cmp     x23, x22
    b.hs    9f
    mov     w0, w20
    add     x1, x21, x23
    sub     x2, x22, x23
    MOVQ    x3, SHELL_WRITE_MAX
    cmp     x2, x3
    csel    x2, x3, x2, hi
    CALL_GLOBAL write
    OS_CHECK 2f, 1b
    b       8f
2:  cbz     x0, 7f
    add     x23, x23, x0
    b       1b
7:  mov     x0, #OS_EIO                     /* no progress */
8:  str     x0, [x19]
9:  str     x23, [x19, #8]
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_append

/* (file, offset, bytes, result): docs/reference/shell.md. x19 result, x20 the file, x21 the bytes, x22 their count, x23 written, x24 the offset. */
FUNCTION lantern_shell_write_at
    ENTER 0
    mov     x19, x3
    stp     xzr, xzr, [x19]
    ldr     x20, [x0]
    ldr     x24, [x1]
    ldr     x21, [x2, #8]
    add     x21, x2, x21
    ldr     x22, [x2, #16]
    mov     x23, #0
1:  cmp     x23, x22
    b.hs    9f
    mov     w0, w20
    add     x1, x21, x23
    sub     x2, x22, x23
    MOVQ    x3, SHELL_WRITE_MAX
    cmp     x2, x3
    csel    x2, x3, x2, hi
    add     x3, x24, x23
    CALL_GLOBAL pwrite
    OS_CHECK 2f, 1b
    b       8f
2:  cbz     x0, 7f
    add     x23, x23, x0
    b       1b
7:  mov     x0, #OS_EIO                     /* no progress */
8:  str     x0, [x19]
9:  str     x23, [x19, #8]
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_write_at

/* (file, result): docs/reference/shell.md. x19 result, x20 the file. */
FUNCTION lantern_shell_sync
    ENTER 0
    mov     x19, x1
    stp     xzr, xzr, [x19]
    ldr     x20, [x0]
1:  mov     w0, w20
    mov     w1, #OS_F_FULLFSYNC
    CALL_GLOBAL fcntl
    OS_CHECK 9f, 1b
2:  mov     w0, w20                         /* the file system does not support F_FULLFSYNC */
    CALL_GLOBAL fsync
    OS_CHECK 9f, 2b
    str     x0, [x19]
9:  mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_sync

/* (file, size, result): docs/reference/shell.md. x19 result, x20 the file, x21 the size. */
FUNCTION lantern_shell_truncate
    ENTER 0
    mov     x19, x2
    stp     xzr, xzr, [x19]
    ldr     x20, [x0]
    ldr     x21, [x1]
1:  mov     w0, w20
    mov     x1, x21
    CALL_GLOBAL ftruncate
    OS_CHECK 9f, 1b
    str     x0, [x19]
9:  mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_truncate

/* (file): docs/reference/shell.md. */
FUNCTION lantern_shell_close
    ENTER 0
    ldr     x0, [x0]
    CALL_GLOBAL close
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_close

/*
 * (path, result): docs/reference/shell.md. x19 result, x20 the file, x21 the size, x22 the
 * memory or an error. Frame: the path, at sp.
 */
FUNCTION lantern_shell_map_file
    ENTER 0
    SHELL_FRAME SHELL_READ_FRAME
    mov     x19, x1
    stp     xzr, xzr, [x19]
    stp     xzr, xzr, [x19, #16]
    mov     x6, sp
    CPATH   x0, x6, 91f
1:  mov     x0, sp
    MOVQ    x1, OS_O_RDONLY_CLOEXEC
    CALL_GLOBAL open
    OS_CHECK 2f, 1b
    b       90f
2:  mov     w20, w0
    mov     w0, w20                         /* its size: the end's offset */
    mov     x1, #0
    mov     w2, #OS_SEEK_END
    CALL_GLOBAL lseek
    cmn     x0, #1
    b.eq    80f
    mov     x21, x0
    cbz     x21, 85f                        /* no bytes: address 0 */
    mov     x0, #0
    mov     x1, x21
    mov     w2, #OS_PROT_READ
    mov     w3, #OS_MAP_SHARED
    mov     w4, w20
    mov     x5, #0
    CALL_GLOBAL mmap
    cmn     x0, #1
    b.eq    80f
    mov     x22, x0
    mov     w0, w20
    CALL_GLOBAL close
    stp     xzr, x22, [x19]
    stp     x21, x21, [x19, #16]
    b       99f
85: mov     w0, w20
    CALL_GLOBAL close
    b       99f
80: OS_ERRNO                                /* the file closes */
    mov     x22, x0
    mov     w0, w20
    CALL_GLOBAL close
    mov     x0, x22
    b       90f
91: mov     x0, #OS_ENAMETOOLONG
90: str     x0, [x19]
99: SHELL_UNFRAME SHELL_READ_FRAME
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_map_file

/* (address, size): docs/reference/shell.md. */
FUNCTION lantern_shell_unmap_file
    ENTER 0
    ldr     x1, [x1]
    ldr     x0, [x0]
    CALL_GLOBAL munmap
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_unmap_file

/* (path, result): docs/reference/shell.md. x19 result. Frame: the path, at sp. */
FUNCTION lantern_shell_remove
    ENTER 0
    SHELL_FRAME SHELL_READ_FRAME
    mov     x19, x1
    stp     xzr, xzr, [x19]
    mov     x6, sp
    CPATH   x0, x6, 91f
1:  mov     x0, sp
    CALL_GLOBAL unlink
    OS_CHECK 99f, 1b
    b       90f
91: mov     x0, #OS_ENAMETOOLONG
90: str     x0, [x19]
99: SHELL_UNFRAME SHELL_READ_FRAME
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_remove

/* (from, to, result): docs/reference/shell.md. x19 result, x20 to. Frame: from at sp, to at sp + 4096. */
FUNCTION lantern_shell_rename
    ENTER 0
    SHELL_FRAME SHELL_TWO_PATHS
    mov     x19, x2
    stp     xzr, xzr, [x19]
    mov     x20, x1
    mov     x6, sp
    CPATH   x0, x6, 91f
    add     x6, sp, #SHELL_READ_FRAME
    CPATH   x20, x6, 91f
1:  mov     x0, sp
    add     x1, sp, #SHELL_READ_FRAME
    CALL_GLOBAL rename
    OS_CHECK 99f, 1b
    b       90f
91: mov     x0, #OS_ENAMETOOLONG
90: str     x0, [x19]
99: SHELL_UNFRAME SHELL_TWO_PATHS
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_rename

/* (path, result): docs/reference/shell.md. x19 result. Frame: the path, at sp. */
FUNCTION lantern_shell_mkdir
    ENTER 0
    SHELL_FRAME SHELL_READ_FRAME
    mov     x19, x1
    stp     xzr, xzr, [x19]
    mov     x6, sp
    CPATH   x0, x6, 91f
1:  mov     x0, sp
    mov     w1, #OS_MODE_DIR
    CALL_GLOBAL mkdir
    OS_CHECK 99f, 1b
    b       90f
91: mov     x0, #OS_ENAMETOOLONG
90: str     x0, [x19]
99: SHELL_UNFRAME SHELL_READ_FRAME
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_mkdir

/* (path, result): docs/reference/shell.md. x19 result, x20 the directory, x21 an error. Frame: the path, at sp. */
FUNCTION lantern_shell_sync_dir
    ENTER 0
    SHELL_FRAME SHELL_READ_FRAME
    mov     x19, x1
    stp     xzr, xzr, [x19]
    mov     x6, sp
    CPATH   x0, x6, 91f
1:  mov     x0, sp
    MOVQ    x1, OS_O_RDONLY_CLOEXEC
    CALL_GLOBAL open
    OS_CHECK 2f, 1b
    b       90f
2:  mov     w20, w0
    mov     x21, #0
3:  mov     w0, w20
    CALL_GLOBAL fsync
    OS_CHECK 4f, 3b
    mov     x21, x0
4:  mov     w0, w20
    CALL_GLOBAL close
    str     x21, [x19]
    b       99f
91: mov     x0, #OS_ENAMETOOLONG
90: str     x0, [x19]
99: SHELL_UNFRAME SHELL_READ_FRAME
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_sync_dir

/* (out): docs/reference/shell.md. x19 out. Locals: struct rusage (144 bytes), then struct rlimit (16). */
FUNCTION lantern_shell_process
    ENTER 160
    mov     x19, x0
    mov     w0, #0                          /* getrusage(RUSAGE_SELF) */
    add     x1, sp, #L
    CALL_GLOBAL getrusage
    ldr     x9, [sp, #L]                    /* user and system seconds; their microseconds are ints */
    ldr     x11, [sp, #(L + 16)]
    add     x9, x9, x11
    MOVQ    x13, 1000000
    mul     x9, x9, x13
    ldrsw   x10, [sp, #(L + 8)]
    ldrsw   x12, [sp, #(L + 24)]
    add     x9, x9, x10
    add     x9, x9, x12
    str     x9, [x19]
    ldr     x9, [sp, #(L + 32)]             /* ru_maxrss, in bytes */
    str     x9, [x19, #8]
    mov     w0, #8                          /* getrlimit(RLIMIT_NOFILE) */
    add     x1, sp, #(L + 144)
    CALL_GLOBAL getrlimit
    mov     x9, #0
    cbnz    w0, 1f
    ldr     x9, [sp, #(L + 144)]
1:  str     x9, [x19, #16]
    mov     x0, #LANTERN_OK
    LEAVE 160
END_FUNCTION lantern_shell_process
