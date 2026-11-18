/*
 * The shell of the lantern binary for Linux on RISC-V: memory, files, the log and the clock,
 * through direct system calls. Requirements: docs/reference/shell.md.
 *
 * System calls: the number in a7, arguments in a0 to a5, "ecall"; a0 holds the result, or minus
 * the error number (-4095 to -1); the other registers keep their values.
 */
.set ISA_RISCV64, 1
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
.set OS_O_RDONLY_CLOEXEC, 0x80000           # O_RDONLY | O_CLOEXEC
.set OS_PROT_RW, 3                          # PROT_READ | PROT_WRITE
.set OS_MAP_PRIVATE_ANON, 0x22              # MAP_PRIVATE | MAP_ANONYMOUS
.set OS_EINTR, 4
.set OS_ENAMETOOLONG, 36
.set OS_CLOCK_REALTIME, 0
.set OS_STAT_SIZE, 48                       # st_size in the generic struct stat
.set SHELL_PATH_MAX, 4095
.set SHELL_READ_FRAME, 4352                 # read_file: 64 the struct stat, 256 the path
.set SYS_MKDIRAT, 34
.set SYS_UNLINKAT, 35
.set SYS_FTRUNCATE, 46
.set SYS_FSYNC, 82
.set SYS_FDATASYNC, 83
.set SYS_RENAMEAT2, 276
.set OS_O_APPEND_CREATE, 0x80441           # O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC
.set OS_MODE_FILE, 420                      # 0644
.set OS_MODE_DIR, 493                       # 0755
.set OS_PROT_READ, 1
.set OS_MAP_SHARED, 1
.set OS_EIO, 5
.set OS_EINVAL, 22
.set SHELL_PATH_FRAME, 4112                 # a path with a zero after it
.set SHELL_TWO_PATHS, 8208                  # two of them: to at 4112

.macro SYSCALL number
    li      a7, \number
    ecall
.endm

/* A leaf with a frame of size bytes, and its one return of LANTERN_OK. */
.macro SHELL_FRAME size
    li      t6, \size
    sub     sp, sp, t6
    UNWIND_ALLOC (\size)
    UNWIND_END_PROLOGUE
.endm

.macro SHELL_RETURN size
    li      a0, LANTERN_OK
    UNWIND_BEGIN_EPILOGUE
    li      t6, \size
    add     sp, sp, t6
    UNWIND_FREE (\size)
    UNWIND_END_EPILOGUE
    ret
.endm

/* The path ByteList at \src as a string with a zero after it at \dst; to \long when above SHELL_PATH_MAX bytes. Uses t2-t5. */
.macro CPATH src, dst, long
    ld      t2, 16(\src)
    li      t3, SHELL_PATH_MAX
    bgtu    t2, t3, \long
    ld      t3, 8(\src)
    add     t3, \src, t3
    li      t4, 0
88: bgeu    t4, t2, 89f
    add     t5, t3, t4
    lbu     t5, 0(t5)
    add     t2, \dst, t4
    sb      t5, 0(t2)
    ld      t2, 16(\src)
    addi    t4, t4, 1
    j       88b
89: add     t5, \dst, t4
    sb      zero, 0(t5)
.endm

/* To label when \reg is minus an error number (-4095 to -1). Uses \tmp. */
.macro IF_ERROR reg, tmp, label
    li      \tmp, -4095
    bgeu    \reg, \tmp, \label
.endm

/* (size, out): docs/reference/shell.md. */
FUNCTION lantern_shell_map
    UNWIND_END_PROLOGUE
    mv      t0, a1
    ld      a1, 0(a0)
    li      a0, 0
    li      a2, OS_PROT_RW
    li      a3, OS_MAP_PRIVATE_ANON
    li      a4, -1
    li      a5, 0
    SYSCALL SYS_MMAP
    IF_ERROR a0, t1, 1f
    j       2f
1:  li      a0, 0                           # no memory: 0
2:  sd      a0, 0(t0)
    li      a0, LANTERN_OK
    ret
END_FUNCTION lantern_shell_map

/* (address, size): docs/reference/shell.md. */
FUNCTION lantern_shell_unmap
    UNWIND_END_PROLOGUE
    ld      a1, 0(a1)
    ld      a0, 0(a0)
    SYSCALL SYS_MUNMAP
    li      a0, LANTERN_OK
    ret
END_FUNCTION lantern_shell_unmap

/*
 * (path, result): docs/reference/shell.md. t0 result, t1 the file, t2 the memory, t3 the file's
 * size, t4 the size mapped (24 more), t5 the bytes read or an error, t6 a check. Frame: 64 a struct stat,
 * 256 the path with a zero after it.
 */
FUNCTION lantern_shell_read_file
    li      t6, SHELL_READ_FRAME
    sub     sp, sp, t6
    UNWIND_ALLOC (SHELL_READ_FRAME)
    UNWIND_END_PROLOGUE
    mv      t0, a1
    sd      zero, 0(t0)
    sd      zero, 8(t0)
    sd      zero, 16(t0)
    sd      zero, 24(t0)
    ld      a2, 16(a0)                      # the path, with a zero after it
    li      t6, SHELL_PATH_MAX
    bgtu    a2, t6, 91f
    ld      a1, 8(a0)
    add     a1, a0, a1
    addi    a3, sp, 256
    li      a4, 0
1:  bgeu    a4, a2, 2f
    add     a5, a1, a4
    lbu     a5, 0(a5)
    add     t6, a3, a4
    sb      a5, 0(t6)
    addi    a4, a4, 1
    j       1b
2:  add     t6, a3, a4
    sb      zero, 0(t6)
    li      a0, OS_AT_FDCWD
    mv      a1, a3
    li      a2, OS_O_RDONLY_CLOEXEC
    li      a3, 0
    SYSCALL SYS_OPENAT
    IF_ERROR a0, t6, 90f
    mv      t1, a0
    addi    a1, sp, 64                      # its size
    SYSCALL SYS_FSTAT
    IF_ERROR a0, t6, 80f
    ld      t3, (64 + OS_STAT_SIZE)(sp)
    addi    t4, t3, 24                      # a ByteList: 24 bytes, then the file's
    li      a0, 0
    mv      a1, t4
    li      a2, OS_PROT_RW
    li      a3, OS_MAP_PRIVATE_ANON
    li      a4, -1
    li      a5, 0
    SYSCALL SYS_MMAP
    IF_ERROR a0, t6, 80f
    mv      t2, a0
    sd      t4, 0(t2)
    li      t6, 24
    sd      t6, 8(t2)
    sd      t3, 16(t2)
    li      t5, 0
4:  bgeu    t5, t3, 5f                      # every byte
    mv      a0, t1
    add     a1, t2, t5
    addi    a1, a1, 24
    sub     a2, t3, t5
    SYSCALL SYS_READ
    li      t6, -OS_EINTR
    beq     a0, t6, 4b
    IF_ERROR a0, t6, 70f
    beqz    a0, 71f
    add     t5, t5, a0
    j       4b
5:  mv      a0, t1
    SYSCALL SYS_CLOSE
    sd      t2, 8(t0)
    sd      t3, 16(t0)
    sd      t4, 24(t0)
    j       99f
71: li      a0, -1                          # the file ends before its size: error 1
70: mv      t5, a0                          # the memory goes back
    mv      a0, t2
    mv      a1, t4
    SYSCALL SYS_MUNMAP
    mv      a0, t5
80: mv      t5, a0                          # the file closes
    mv      a0, t1
    SYSCALL SYS_CLOSE
    mv      a0, t5
90: neg     a0, a0                          # the error
    sd      a0, 0(t0)
    j       99f
91: li      a0, -OS_ENAMETOOLONG
    j       90b
99: li      a0, LANTERN_OK
    UNWIND_BEGIN_EPILOGUE
    li      t6, SHELL_READ_FRAME
    add     sp, sp, t6
    UNWIND_FREE (SHELL_READ_FRAME)
    UNWIND_END_EPILOGUE
    ret
END_FUNCTION lantern_shell_read_file

/* (stream, bytes): docs/reference/shell.md. t0 the file, t1 the next byte, t2 the bytes left. */
FUNCTION lantern_shell_write
    UNWIND_END_PROLOGUE
    ld      t0, 0(a0)
    ld      t1, 8(a1)
    add     t1, a1, t1
    ld      t2, 16(a1)
1:  beqz    t2, 9f
    mv      a0, t0
    mv      a1, t1
    mv      a2, t2
    SYSCALL SYS_WRITE
    li      t3, -OS_EINTR
    beq     a0, t3, 1b
    IF_ERROR a0, t3, 9f
    add     t1, t1, a0
    sub     t2, t2, a0
    j       1b
9:  li      a0, LANTERN_OK
    ret
END_FUNCTION lantern_shell_write

/* (out): docs/reference/shell.md. Frame: a struct timespec. */
FUNCTION lantern_shell_time_ms
    addi    sp, sp, -16
    UNWIND_ALLOC 16
    UNWIND_END_PROLOGUE
    mv      t0, a0
    li      a0, OS_CLOCK_REALTIME
    mv      a1, sp
    SYSCALL SYS_CLOCK_GETTIME
    ld      t1, 0(sp)                       # seconds * 1000 + nanoseconds / 10^6
    ld      t2, 8(sp)
    li      t3, 1000
    mul     t1, t1, t3
    li      t3, 1000000
    divu    t2, t2, t3
    add     t1, t1, t2
    sd      t1, 0(t0)
    li      a0, LANTERN_OK
    UNWIND_BEGIN_EPILOGUE
    addi    sp, sp, 16
    UNWIND_FREE 16
    UNWIND_END_EPILOGUE
    ret
END_FUNCTION lantern_shell_time_ms

/* (path, mode, result): docs/reference/shell.md. t0 result, t1 the flags. Frame: the path. */
FUNCTION lantern_shell_open
    SHELL_FRAME SHELL_PATH_FRAME
    mv      t0, a2
    sd      zero, 0(t0)
    sd      zero, 8(t0)
    ld      t1, 0(a1)
    li      t2, 1
    bgtu    t1, t2, 92f
    li      t3, OS_O_RDONLY_CLOEXEC
    bne     t1, t2, 1f
    li      t3, OS_O_APPEND_CREATE
1:  mv      t1, t3
    CPATH   a0, sp, 91f
2:  li      a0, OS_AT_FDCWD
    mv      a1, sp
    mv      a2, t1
    li      a3, OS_MODE_FILE
    SYSCALL SYS_OPENAT
    li      t2, -OS_EINTR
    beq     a0, t2, 2b
    IF_ERROR a0, t2, 90f
    sd      a0, 8(t0)
    j       99f
92: li      a0, -OS_EINVAL
    j       90f
91: li      a0, -OS_ENAMETOOLONG
90: neg     a0, a0
    sd      a0, 0(t0)
99: SHELL_RETURN SHELL_PATH_FRAME
END_FUNCTION lantern_shell_open

/* (file, bytes, result): docs/reference/shell.md. t0 result, t1 the file, t2 the bytes, t3 their count, t4 written. */
FUNCTION lantern_shell_append
    UNWIND_END_PROLOGUE
    mv      t0, a2
    sd      zero, 0(t0)
    sd      zero, 8(t0)
    ld      t1, 0(a0)
    ld      t2, 8(a1)
    add     t2, a1, t2
    ld      t3, 16(a1)
    li      t4, 0
1:  bgeu    t4, t3, 9f
    mv      a0, t1
    add     a1, t2, t4
    sub     a2, t3, t4
    SYSCALL SYS_WRITE
    li      t5, -OS_EINTR
    beq     a0, t5, 1b
    IF_ERROR a0, t5, 8f
    beqz    a0, 7f
    add     t4, t4, a0
    j       1b
7:  li      a0, -OS_EIO                     # no progress
8:  neg     a0, a0
    sd      a0, 0(t0)
9:  sd      t4, 8(t0)
    li      a0, LANTERN_OK
    ret
END_FUNCTION lantern_shell_append

/* (file, result): docs/reference/shell.md. t0 result, t1 the file. */
FUNCTION lantern_shell_sync
    UNWIND_END_PROLOGUE
    mv      t0, a1
    sd      zero, 0(t0)
    sd      zero, 8(t0)
    ld      t1, 0(a0)
1:  mv      a0, t1
    SYSCALL SYS_FDATASYNC
    li      t2, -OS_EINTR
    beq     a0, t2, 1b
    IF_ERROR a0, t2, 90f
    j       99f
90: neg     a0, a0
    sd      a0, 0(t0)
99: li      a0, LANTERN_OK
    ret
END_FUNCTION lantern_shell_sync

/* (file, size, result): docs/reference/shell.md. t0 result, t1 the file, t3 the size. */
FUNCTION lantern_shell_truncate
    UNWIND_END_PROLOGUE
    mv      t0, a2
    sd      zero, 0(t0)
    sd      zero, 8(t0)
    ld      t1, 0(a0)
    ld      t3, 0(a1)
1:  mv      a0, t1
    mv      a1, t3
    SYSCALL SYS_FTRUNCATE
    li      t2, -OS_EINTR
    beq     a0, t2, 1b
    IF_ERROR a0, t2, 90f
    j       99f
90: neg     a0, a0
    sd      a0, 0(t0)
99: li      a0, LANTERN_OK
    ret
END_FUNCTION lantern_shell_truncate

/* (file): docs/reference/shell.md. */
FUNCTION lantern_shell_close
    UNWIND_END_PROLOGUE
    ld      a0, 0(a0)
    SYSCALL SYS_CLOSE
    li      a0, LANTERN_OK
    ret
END_FUNCTION lantern_shell_close

/*
 * (path, result): docs/reference/shell.md. t0 result, t1 the file, a6 the memory (kept by the
 * system call), t6 the size. Frame: 64 a struct stat, 256 the path.
 */
FUNCTION lantern_shell_map_file
    SHELL_FRAME SHELL_READ_FRAME
    mv      t0, a1
    sd      zero, 0(t0)
    sd      zero, 8(t0)
    sd      zero, 16(t0)
    sd      zero, 24(t0)
    addi    t1, sp, 256
    CPATH   a0, t1, 91f
1:  li      a0, OS_AT_FDCWD
    addi    a1, sp, 256
    li      a2, OS_O_RDONLY_CLOEXEC
    li      a3, 0
    SYSCALL SYS_OPENAT
    li      t2, -OS_EINTR
    beq     a0, t2, 1b
    IF_ERROR a0, t2, 90f
    mv      t1, a0
    addi    a1, sp, 64                      # its size
    SYSCALL SYS_FSTAT
    IF_ERROR a0, t2, 80f
    ld      t6, (64 + OS_STAT_SIZE)(sp)
    beqz    t6, 85f                         # no bytes: address 0
    li      a0, 0
    mv      a1, t6
    li      a2, OS_PROT_READ
    li      a3, OS_MAP_SHARED
    mv      a4, t1
    li      a5, 0
    SYSCALL SYS_MMAP
    IF_ERROR a0, t2, 80f
    mv      a6, a0
    mv      a0, t1
    SYSCALL SYS_CLOSE
    sd      a6, 8(t0)
    sd      t6, 16(t0)
    sd      t6, 24(t0)
    j       99f
85: mv      a0, t1
    SYSCALL SYS_CLOSE
    j       99f
80: mv      t3, a0                          # the file closes
    mv      a0, t1
    SYSCALL SYS_CLOSE
    mv      a0, t3
    j       90f
91: li      a0, -OS_ENAMETOOLONG
90: neg     a0, a0
    sd      a0, 0(t0)
99: SHELL_RETURN SHELL_READ_FRAME
END_FUNCTION lantern_shell_map_file

/* (address, size): docs/reference/shell.md. */
FUNCTION lantern_shell_unmap_file
    UNWIND_END_PROLOGUE
    ld      a1, 0(a1)
    ld      a0, 0(a0)
    SYSCALL SYS_MUNMAP
    li      a0, LANTERN_OK
    ret
END_FUNCTION lantern_shell_unmap_file

/* (path, result): docs/reference/shell.md. t0 result. Frame: the path. */
FUNCTION lantern_shell_remove
    SHELL_FRAME SHELL_PATH_FRAME
    mv      t0, a1
    sd      zero, 0(t0)
    sd      zero, 8(t0)
    CPATH   a0, sp, 91f
1:  li      a0, OS_AT_FDCWD
    mv      a1, sp
    li      a2, 0
    SYSCALL SYS_UNLINKAT
    li      t2, -OS_EINTR
    beq     a0, t2, 1b
    IF_ERROR a0, t2, 90f
    j       99f
91: li      a0, -OS_ENAMETOOLONG
90: neg     a0, a0
    sd      a0, 0(t0)
99: SHELL_RETURN SHELL_PATH_FRAME
END_FUNCTION lantern_shell_remove

/* (from, to, result): docs/reference/shell.md. t0 result, t1 to. Frame: from, then to at SHELL_PATH_FRAME. */
FUNCTION lantern_shell_rename
    SHELL_FRAME SHELL_TWO_PATHS
    mv      t0, a2
    sd      zero, 0(t0)
    sd      zero, 8(t0)
    mv      t1, a1
    CPATH   a0, sp, 91f
    li      t6, SHELL_PATH_FRAME
    add     a3, sp, t6
    CPATH   t1, a3, 91f
1:  li      a0, OS_AT_FDCWD
    mv      a1, sp
    li      a2, OS_AT_FDCWD
    li      t6, SHELL_PATH_FRAME
    add     a3, sp, t6
    li      a4, 0
    SYSCALL SYS_RENAMEAT2
    li      t2, -OS_EINTR
    beq     a0, t2, 1b
    IF_ERROR a0, t2, 90f
    j       99f
91: li      a0, -OS_ENAMETOOLONG
90: neg     a0, a0
    sd      a0, 0(t0)
99: SHELL_RETURN SHELL_TWO_PATHS
END_FUNCTION lantern_shell_rename

/* (path, result): docs/reference/shell.md. t0 result. Frame: the path. */
FUNCTION lantern_shell_mkdir
    SHELL_FRAME SHELL_PATH_FRAME
    mv      t0, a1
    sd      zero, 0(t0)
    sd      zero, 8(t0)
    CPATH   a0, sp, 91f
1:  li      a0, OS_AT_FDCWD
    mv      a1, sp
    li      a2, OS_MODE_DIR
    SYSCALL SYS_MKDIRAT
    li      t2, -OS_EINTR
    beq     a0, t2, 1b
    IF_ERROR a0, t2, 90f
    j       99f
91: li      a0, -OS_ENAMETOOLONG
90: neg     a0, a0
    sd      a0, 0(t0)
99: SHELL_RETURN SHELL_PATH_FRAME
END_FUNCTION lantern_shell_mkdir

/* (path, result): docs/reference/shell.md. t0 result, t1 the directory, t3 an error. Frame: the path. */
FUNCTION lantern_shell_sync_dir
    SHELL_FRAME SHELL_PATH_FRAME
    mv      t0, a1
    sd      zero, 0(t0)
    sd      zero, 8(t0)
    CPATH   a0, sp, 91f
1:  li      a0, OS_AT_FDCWD
    mv      a1, sp
    li      a2, OS_O_RDONLY_CLOEXEC
    li      a3, 0
    SYSCALL SYS_OPENAT
    li      t2, -OS_EINTR
    beq     a0, t2, 1b
    IF_ERROR a0, t2, 90f
    mv      t1, a0
2:  mv      a0, t1
    SYSCALL SYS_FSYNC
    li      t2, -OS_EINTR
    beq     a0, t2, 2b
    mv      t3, a0
    mv      a0, t1
    SYSCALL SYS_CLOSE
    mv      a0, t3
    IF_ERROR a0, t2, 90f
    j       99f
91: li      a0, -OS_ENAMETOOLONG
90: neg     a0, a0
    sd      a0, 0(t0)
99: SHELL_RETURN SHELL_PATH_FRAME
END_FUNCTION lantern_shell_sync_dir
