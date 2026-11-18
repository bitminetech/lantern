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

.macro SYSCALL number
    li      a7, \number
    ecall
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
