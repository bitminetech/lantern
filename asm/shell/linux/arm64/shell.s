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
.set SYS_MKDIRAT, 34
.set SYS_UNLINKAT, 35
.set SYS_FTRUNCATE, 46
.set SYS_FSYNC, 82
.set SYS_FDATASYNC, 83
.set SYS_PWRITE64, 68
.set SYS_RENAMEAT2, 276
.set OS_O_APPEND_CREATE, 0x80441           /* O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC */
.set OS_O_RDWR_CREATE, 0x80042             /* O_RDWR | O_CREAT | O_CLOEXEC */
.set OS_MODE_FILE, 420                      /* 0644 */
.set OS_MODE_DIR, 493                       /* 0755 */
.set OS_PROT_READ, 1
.set OS_MAP_SHARED, 1
.set OS_EIO, 5
.set OS_EINVAL, 22
.set SHELL_PATH_FRAME, 4096                 /* a path with a zero after it */
.set SHELL_TWO_PATHS, 8192                  /* two of them */

.macro SYSCALL number
    mov     x8, #\number
    svc     #0
.endm

/* A leaf with a frame of size bytes, and its one return of LANTERN_OK. */
.macro SHELL_FRAME size
    sub     sp, sp, #(\size)
    UNWIND_ALLOC (\size)
    UNWIND_END_PROLOGUE
.endm

.macro SHELL_RETURN size
    mov     x0, #LANTERN_OK
    UNWIND_BEGIN_EPILOGUE
    add     sp, sp, #(\size)
    UNWIND_FREE (\size)
    UNWIND_END_EPILOGUE
    ret
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
 * file's size, x13 the size mapped (24 more), x14 the bytes read or an error. Frame: 64 a struct stat,
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
    add     x13, x12, #24                   /* a ByteList: 24 bytes, then the file's */
    mov     x0, #0
    mov     x1, x13
    mov     x2, #OS_PROT_RW
    mov     x3, #OS_MAP_PRIVATE_ANON
    mov     x4, #-1
    mov     x5, #0
    SYSCALL SYS_MMAP
    IF_ERROR x0, 80f
    mov     x11, x0
    mov     x2, #24
    stp     x13, x2, [x11]
    str     x12, [x11, #16]
    mov     x14, #0
4:  cmp     x14, x12                        /* every byte */
    b.hs    5f
    mov     x0, x10
    add     x1, x11, x14
    add     x1, x1, #24
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

/* (path, mode, result): docs/reference/shell.md. x9 result, x10 the flags. Frame: the path. */
FUNCTION lantern_shell_open
    SHELL_FRAME SHELL_PATH_FRAME
    mov     x9, x2
    stp     xzr, xzr, [x9]
    ldr     x10, [x1]
    cmp     x10, #2
    b.hi    92f
    mov     x11, #OS_O_RDONLY_CLOEXEC
    MOVQ    x12, OS_O_APPEND_CREATE
    cmp     x10, #1
    csel    x11, x12, x11, eq
    MOVQ    x12, OS_O_RDWR_CREATE
    cmp     x10, #2
    csel    x10, x12, x11, eq
    mov     x6, sp
    CPATH   x0, x6, 91f
1:  mov     x0, #OS_AT_FDCWD
    mov     x1, sp
    mov     x2, x10
    mov     x3, #OS_MODE_FILE
    SYSCALL SYS_OPENAT
    cmn     x0, #OS_EINTR
    b.eq    1b
    IF_ERROR x0, 90f
    str     x0, [x9, #8]
    b       99f
92: mov     x0, #-OS_EINVAL
    b       90f
91: mov     x0, #-OS_ENAMETOOLONG
90: neg     x0, x0
    str     x0, [x9]
99: SHELL_RETURN SHELL_PATH_FRAME
END_FUNCTION lantern_shell_open

/* (file, bytes, result): docs/reference/shell.md. x9 result, x10 the file, x11 the bytes, x12 their count, x13 written. */
FUNCTION lantern_shell_append
    UNWIND_END_PROLOGUE
    mov     x9, x2
    stp     xzr, xzr, [x9]
    ldr     x10, [x0]
    ldp     x11, x12, [x1, #8]
    add     x11, x1, x11
    mov     x13, #0
1:  cmp     x13, x12
    b.hs    9f
    mov     x0, x10
    add     x1, x11, x13
    sub     x2, x12, x13
    SYSCALL SYS_WRITE
    cmn     x0, #OS_EINTR
    b.eq    1b
    IF_ERROR x0, 8f
    cbz     x0, 7f
    add     x13, x13, x0
    b       1b
7:  mov     x0, #-OS_EIO                    /* no progress */
8:  neg     x0, x0
    str     x0, [x9]
9:  str     x13, [x9, #8]
    mov     x0, #LANTERN_OK
    ret
END_FUNCTION lantern_shell_append

/* (file, offset, bytes, result): docs/reference/shell.md. x9 result, x10 the file, x11 the bytes, x12 their count, x13 written, x14 the offset. */
FUNCTION lantern_shell_write_at
    UNWIND_END_PROLOGUE
    mov     x9, x3
    stp     xzr, xzr, [x9]
    ldr     x10, [x0]
    ldr     x14, [x1]
    ldp     x11, x12, [x2, #8]
    add     x11, x2, x11
    mov     x13, #0
1:  cmp     x13, x12
    b.hs    9f
    mov     x0, x10
    add     x1, x11, x13
    sub     x2, x12, x13
    add     x3, x14, x13
    SYSCALL SYS_PWRITE64
    cmn     x0, #OS_EINTR
    b.eq    1b
    IF_ERROR x0, 8f
    cbz     x0, 7f
    add     x13, x13, x0
    b       1b
7:  mov     x0, #-OS_EIO                    /* no progress */
8:  neg     x0, x0
    str     x0, [x9]
9:  str     x13, [x9, #8]
    mov     x0, #LANTERN_OK
    ret
END_FUNCTION lantern_shell_write_at

/* (file, result): docs/reference/shell.md. x9 result, x10 the file. */
FUNCTION lantern_shell_sync
    UNWIND_END_PROLOGUE
    mov     x9, x1
    stp     xzr, xzr, [x9]
    ldr     x10, [x0]
1:  mov     x0, x10
    SYSCALL SYS_FDATASYNC
    cmn     x0, #OS_EINTR
    b.eq    1b
    IF_ERROR x0, 90f
    b       99f
90: neg     x0, x0
    str     x0, [x9]
99: mov     x0, #LANTERN_OK
    ret
END_FUNCTION lantern_shell_sync

/* (file, size, result): docs/reference/shell.md. x9 result, x10 the file, x11 the size. */
FUNCTION lantern_shell_truncate
    UNWIND_END_PROLOGUE
    mov     x9, x2
    stp     xzr, xzr, [x9]
    ldr     x10, [x0]
    ldr     x11, [x1]
1:  mov     x0, x10
    mov     x1, x11
    SYSCALL SYS_FTRUNCATE
    cmn     x0, #OS_EINTR
    b.eq    1b
    IF_ERROR x0, 90f
    b       99f
90: neg     x0, x0
    str     x0, [x9]
99: mov     x0, #LANTERN_OK
    ret
END_FUNCTION lantern_shell_truncate

/* (file): docs/reference/shell.md. */
FUNCTION lantern_shell_close
    UNWIND_END_PROLOGUE
    ldr     x0, [x0]
    SYSCALL SYS_CLOSE
    mov     x0, #LANTERN_OK
    ret
END_FUNCTION lantern_shell_close

/*
 * (path, result): docs/reference/shell.md. x9 result, x10 the file, x11 the memory, x12 the
 * file's size, x14 an error. Frame: 64 a struct stat, 256 the path.
 */
FUNCTION lantern_shell_map_file
    SHELL_FRAME SHELL_READ_FRAME
    mov     x9, x1
    stp     xzr, xzr, [x9]
    stp     xzr, xzr, [x9, #16]
    add     x6, sp, #256
    CPATH   x0, x6, 91f
1:  mov     x0, #OS_AT_FDCWD
    add     x1, sp, #256
    mov     x2, #OS_O_RDONLY_CLOEXEC
    mov     x3, #0
    SYSCALL SYS_OPENAT
    cmn     x0, #OS_EINTR
    b.eq    1b
    IF_ERROR x0, 90f
    mov     x10, x0
    add     x1, sp, #64                     /* its size */
    SYSCALL SYS_FSTAT
    IF_ERROR x0, 80f
    ldr     x12, [sp, #(64 + OS_STAT_SIZE)]
    cbz     x12, 85f                        /* no bytes: address 0 */
    mov     x0, #0
    mov     x1, x12
    mov     x2, #OS_PROT_READ
    mov     x3, #OS_MAP_SHARED
    mov     x4, x10
    mov     x5, #0
    SYSCALL SYS_MMAP
    IF_ERROR x0, 80f
    mov     x11, x0
    mov     x0, x10
    SYSCALL SYS_CLOSE
    stp     xzr, x11, [x9]
    stp     x12, x12, [x9, #16]
    b       99f
85: mov     x0, x10
    SYSCALL SYS_CLOSE
    b       99f
80: mov     x14, x0                         /* the file closes */
    mov     x0, x10
    SYSCALL SYS_CLOSE
    mov     x0, x14
    b       90f
91: mov     x0, #-OS_ENAMETOOLONG
90: neg     x0, x0
    str     x0, [x9]
99: SHELL_RETURN SHELL_READ_FRAME
END_FUNCTION lantern_shell_map_file

/* (address, size): docs/reference/shell.md. */
FUNCTION lantern_shell_unmap_file
    UNWIND_END_PROLOGUE
    ldr     x1, [x1]
    ldr     x0, [x0]
    SYSCALL SYS_MUNMAP
    mov     x0, #LANTERN_OK
    ret
END_FUNCTION lantern_shell_unmap_file

/* (path, result): docs/reference/shell.md. x9 result. Frame: the path. */
FUNCTION lantern_shell_remove
    SHELL_FRAME SHELL_PATH_FRAME
    mov     x9, x1
    stp     xzr, xzr, [x9]
    mov     x6, sp
    CPATH   x0, x6, 91f
1:  mov     x0, #OS_AT_FDCWD
    mov     x1, sp
    mov     x2, #0
    SYSCALL SYS_UNLINKAT
    cmn     x0, #OS_EINTR
    b.eq    1b
    IF_ERROR x0, 90f
    b       99f
91: mov     x0, #-OS_ENAMETOOLONG
90: neg     x0, x0
    str     x0, [x9]
99: SHELL_RETURN SHELL_PATH_FRAME
END_FUNCTION lantern_shell_remove

/* (from, to, result): docs/reference/shell.md. x7 to, x9 result. Frame: from, then to at 4096. */
FUNCTION lantern_shell_rename
    SHELL_FRAME SHELL_TWO_PATHS
    mov     x9, x2
    stp     xzr, xzr, [x9]
    mov     x7, x1
    mov     x6, sp
    CPATH   x0, x6, 91f
    add     x6, sp, #SHELL_PATH_FRAME
    CPATH   x7, x6, 91f
1:  mov     x0, #OS_AT_FDCWD
    mov     x1, sp
    mov     x2, #OS_AT_FDCWD
    add     x3, sp, #SHELL_PATH_FRAME
    mov     x4, #0
    SYSCALL SYS_RENAMEAT2
    cmn     x0, #OS_EINTR
    b.eq    1b
    IF_ERROR x0, 90f
    b       99f
91: mov     x0, #-OS_ENAMETOOLONG
90: neg     x0, x0
    str     x0, [x9]
99: SHELL_RETURN SHELL_TWO_PATHS
END_FUNCTION lantern_shell_rename

/* (path, result): docs/reference/shell.md. x9 result. Frame: the path. */
FUNCTION lantern_shell_mkdir
    SHELL_FRAME SHELL_PATH_FRAME
    mov     x9, x1
    stp     xzr, xzr, [x9]
    mov     x6, sp
    CPATH   x0, x6, 91f
1:  mov     x0, #OS_AT_FDCWD
    mov     x1, sp
    mov     x2, #OS_MODE_DIR
    SYSCALL SYS_MKDIRAT
    cmn     x0, #OS_EINTR
    b.eq    1b
    IF_ERROR x0, 90f
    b       99f
91: mov     x0, #-OS_ENAMETOOLONG
90: neg     x0, x0
    str     x0, [x9]
99: SHELL_RETURN SHELL_PATH_FRAME
END_FUNCTION lantern_shell_mkdir

/* (path, result): docs/reference/shell.md. x9 result, x10 the directory, x14 an error. Frame: the path. */
FUNCTION lantern_shell_sync_dir
    SHELL_FRAME SHELL_PATH_FRAME
    mov     x9, x1
    stp     xzr, xzr, [x9]
    mov     x6, sp
    CPATH   x0, x6, 91f
1:  mov     x0, #OS_AT_FDCWD
    mov     x1, sp
    mov     x2, #OS_O_RDONLY_CLOEXEC
    mov     x3, #0
    SYSCALL SYS_OPENAT
    cmn     x0, #OS_EINTR
    b.eq    1b
    IF_ERROR x0, 90f
    mov     x10, x0
2:  mov     x0, x10
    SYSCALL SYS_FSYNC
    cmn     x0, #OS_EINTR
    b.eq    2b
    mov     x14, x0
    mov     x0, x10
    SYSCALL SYS_CLOSE
    mov     x0, x14
    IF_ERROR x0, 90f
    b       99f
91: mov     x0, #-OS_ENAMETOOLONG
90: neg     x0, x0
    str     x0, [x9]
99: SHELL_RETURN SHELL_PATH_FRAME
END_FUNCTION lantern_shell_sync_dir

.set SYS_GETRUSAGE, 165
.set SYS_PRLIMIT64, 261

/* (out): docs/reference/shell.md. Frame: struct rusage (144 bytes), struct rlimit (16), then out. */
FUNCTION lantern_shell_process
    SHELL_FRAME 176
    str     x0, [sp, #160]
    mov     x0, #0                          /* getrusage(RUSAGE_SELF) */
    mov     x1, sp
    SYSCALL SYS_GETRUSAGE
    ldp     x9, x10, [sp]                   /* user seconds and microseconds; then system */
    ldp     x11, x12, [sp, #16]
    add     x9, x9, x11
    MOVQ    x13, 1000000
    mul     x9, x9, x13
    add     x9, x9, x10
    add     x9, x9, x12
    ldr     x13, [sp, #160]
    str     x9, [x13]
    ldr     x9, [sp, #32]                   /* ru_maxrss, in KiB */
    lsl     x9, x9, #10
    str     x9, [x13, #8]
    mov     x0, #0                          /* prlimit64(0, RLIMIT_NOFILE, NULL, &old) */
    mov     x1, #7
    mov     x2, #0
    add     x3, sp, #144
    SYSCALL SYS_PRLIMIT64
    mov     x9, #0
    cbnz    x0, 1f
    ldr     x9, [sp, #144]
1:  ldr     x13, [sp, #160]
    str     x9, [x13, #16]
    SHELL_RETURN 176
END_FUNCTION lantern_shell_process
