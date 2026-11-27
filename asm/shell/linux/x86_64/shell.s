/*
 * The shell of the lantern binary for Linux on x86-64: memory, files, the log and the clock,
 * through direct system calls. Requirements: docs/reference/shell.md.
 *
 * System calls: the number in rax, arguments in rdi, rsi, rdx, r10, r8, r9, "syscall"; rax holds
 * the result, or minus the error number (-4095 to -1); rcx and r11 change.
 */
.set ISA_X86_64, 1
.include "ssz.inc"
.include "crypto.inc"
.include "bls12381.inc"
.include "kzg.inc"
.include "preset.inc"
.include "lantern.inc"
.include "platform.inc"
.include "macros.s"

/* Linux numbers: arch/x86/entry/syscalls/syscall_64.tbl and the uapi headers. */
.set SYS_READ, 0
.set SYS_WRITE, 1
.set SYS_CLOSE, 3
.set SYS_FSTAT, 5
.set SYS_MMAP, 9
.set SYS_MUNMAP, 11
.set SYS_CLOCK_GETTIME, 228
.set SYS_OPENAT, 257
.set OS_AT_FDCWD, -100
.set OS_O_RDONLY_CLOEXEC, 0x80000           /* O_RDONLY | O_CLOEXEC */
.set OS_PROT_RW, 3                          /* PROT_READ | PROT_WRITE */
.set OS_MAP_PRIVATE_ANON, 0x22              /* MAP_PRIVATE | MAP_ANONYMOUS */
.set OS_EINTR, 4
.set OS_ENAMETOOLONG, 36
.set OS_CLOCK_REALTIME, 0
.set OS_STAT_SIZE, 48                       /* st_size in struct stat */
.set SHELL_PATH_MAX, 4095
.set SYS_FSYNC, 74
.set SYS_FDATASYNC, 75
.set SYS_PWRITE64, 18
.set SYS_FTRUNCATE, 77
.set SYS_MKDIRAT, 258
.set SYS_UNLINKAT, 263
.set SYS_RENAMEAT2, 316
.set OS_O_APPEND_CREATE, 0x80441           # O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC
.set OS_O_RDWR_CREATE, 0x80042             # O_RDWR | O_CREAT | O_CLOEXEC
.set OS_MODE_FILE, 420                      # 0644
.set OS_MODE_DIR, 493                       # 0755
.set OS_PROT_READ, 1
.set OS_MAP_SHARED, 1
.set OS_EIO, 5
.set OS_EINVAL, 22
.set SHELL_PATH_FRAME, 4112                 # L the result, L+16 a path with a zero after it
.set SHELL_TWO_PATHS, 8208                  # L the result, L+8 to, L+16 from, L+4112 to

# The path ByteList at rax as a string with a zero after it at \at(%rsp); to \long when above SHELL_PATH_MAX bytes. Uses rcx, rsi, rdi.
.macro CPATH at, long
    mov     16(%rax), %rcx
    cmp     $SHELL_PATH_MAX, %rcx
    ja      \long
    mov     8(%rax), %rsi
    add     %rax, %rsi
    lea     \at(%rsp), %rdi
    rep movsb
    movb    $0, (%rdi)
.endm

# The result at L(%rsp) takes minus the error rax; then the return of LANTERN_OK.
.macro SHELL_ERROR locals
    neg     %rax
    mov     L(%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
    LEAVE \locals
.endm

.macro SYSCALL number
    mov     $(\number), %eax
    syscall
.endm

/* (size, out): docs/reference/shell.md. */
FUNCTION lantern_shell_map
    FRAME 16
    mov     %rsi, (%rsp)
    mov     (%rdi), %rsi
    xor     %edi, %edi
    mov     $OS_PROT_RW, %edx
    mov     $OS_MAP_PRIVATE_ANON, %r10d
    mov     $-1, %r8
    xor     %r9d, %r9d
    SYSCALL SYS_MMAP
    cmp     $-4095, %rax
    jb      1f
    xor     %eax, %eax                      # no memory: 0
1:  mov     (%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
    UNFRAME 16
END_FUNCTION lantern_shell_map

/* (address, size): docs/reference/shell.md. */
FUNCTION lantern_shell_unmap
    FRAME 0
    mov     (%rsi), %rsi
    mov     (%rdi), %rdi
    SYSCALL SYS_MUNMAP
    xor     %eax, %eax
    UNFRAME 0
END_FUNCTION lantern_shell_unmap

/*
 * (path, result): docs/reference/shell.md. Locals: L result, L+8 the file, L+16 the memory,
 * L+24 the file's size, L+32 the size mapped (24 more), L+40 the bytes read or an error, L+48 a struct
 * stat (144 bytes), L+192 the path with a zero after it (4096 bytes).
 */
FUNCTION lantern_shell_read_file
    ENTER 4304
    mov     %rsi, L(%rsp)
    movq    $0, (%rsi)
    movq    $0, 8(%rsi)
    movq    $0, 16(%rsi)
    movq    $0, 24(%rsi)
    mov     16(%rdi), %rcx                  # the path, with a zero after it
    cmp     $SHELL_PATH_MAX, %rcx
    ja      91f
    mov     8(%rdi), %rsi
    add     %rdi, %rsi
    lea     (L + 192)(%rsp), %rdi
    rep movsb
    movb    $0, (%rdi)
    mov     $OS_AT_FDCWD, %rdi
    lea     (L + 192)(%rsp), %rsi
    mov     $OS_O_RDONLY_CLOEXEC, %edx
    xor     %r10d, %r10d
    SYSCALL SYS_OPENAT
    cmp     $-4095, %rax
    jae     90f
    mov     %rax, (L + 8)(%rsp)
    mov     %rax, %rdi                      # its size
    lea     (L + 48)(%rsp), %rsi
    SYSCALL SYS_FSTAT
    cmp     $-4095, %rax
    jae     80f
    mov     (L + 48 + OS_STAT_SIZE)(%rsp), %rsi
    mov     %rsi, (L + 24)(%rsp)
    add     $24, %rsi                       # a ByteList: 24 bytes, then the file's
    mov     %rsi, (L + 32)(%rsp)
    xor     %edi, %edi
    mov     $OS_PROT_RW, %edx
    mov     $OS_MAP_PRIVATE_ANON, %r10d
    mov     $-1, %r8
    xor     %r9d, %r9d
    SYSCALL SYS_MMAP
    cmp     $-4095, %rax
    jae     80f
    mov     %rax, (L + 16)(%rsp)
    mov     (L + 32)(%rsp), %rcx
    mov     %rcx, (%rax)
    movq    $24, 8(%rax)
    mov     (L + 24)(%rsp), %rcx
    mov     %rcx, 16(%rax)
    movq    $0, (L + 40)(%rsp)
2:  mov     (L + 40)(%rsp), %rsi            # every byte
    cmp     (L + 24)(%rsp), %rsi
    jae     3f
    mov     (L + 8)(%rsp), %rdi
    mov     (L + 24)(%rsp), %rdx
    sub     %rsi, %rdx
    add     (L + 16)(%rsp), %rsi
    add     $24, %rsi
    SYSCALL SYS_READ
    cmp     $-OS_EINTR, %rax
    je      2b
    cmp     $-4095, %rax
    jae     70f
    test    %rax, %rax
    jz      71f
    add     %rax, (L + 40)(%rsp)
    jmp     2b
3:  mov     (L + 8)(%rsp), %rdi
    SYSCALL SYS_CLOSE
    mov     L(%rsp), %rcx
    mov     (L + 16)(%rsp), %rax
    mov     %rax, 8(%rcx)
    mov     (L + 24)(%rsp), %rax
    mov     %rax, 16(%rcx)
    mov     (L + 32)(%rsp), %rax
    mov     %rax, 24(%rcx)
    xor     %eax, %eax
    LEAVE 4304
71: mov     $-1, %rax                       # the file ends before its size: error 1
70: mov     %rax, (L + 40)(%rsp)            # the memory goes back
    mov     (L + 16)(%rsp), %rdi
    mov     (L + 32)(%rsp), %rsi
    SYSCALL SYS_MUNMAP
    mov     (L + 40)(%rsp), %rax
80: mov     %rax, (L + 40)(%rsp)            # the file closes
    mov     (L + 8)(%rsp), %rdi
    SYSCALL SYS_CLOSE
    mov     (L + 40)(%rsp), %rax
90: neg     %rax                            # the error
    mov     L(%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
    LEAVE 4304
91: mov     $-OS_ENAMETOOLONG, %rax
    jmp     90b
END_FUNCTION lantern_shell_read_file

/* (stream, bytes): docs/reference/shell.md. rbx the file, rbp the next byte, r12 the bytes left. */
FUNCTION lantern_shell_write
    ENTER 0
    mov     (%rdi), %rbx
    mov     8(%rsi), %rbp
    add     %rsi, %rbp
    mov     16(%rsi), %r12
1:  test    %r12, %r12
    jz      9f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    SYSCALL SYS_WRITE
    cmp     $-OS_EINTR, %rax
    je      1b
    cmp     $-4095, %rax
    jae     9f
    add     %rax, %rbp
    sub     %rax, %r12
    jmp     1b
9:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_write

/* (out): docs/reference/shell.md. Locals: 0 out, 8 a struct timespec. */
FUNCTION lantern_shell_time_ms
    FRAME 32
    mov     %rdi, (%rsp)
    mov     $OS_CLOCK_REALTIME, %edi
    lea     8(%rsp), %rsi
    SYSCALL SYS_CLOCK_GETTIME
    mov     16(%rsp), %rax                  # seconds * 1000 + nanoseconds / 10^6
    xor     %edx, %edx
    mov     $1000000, %ecx
    div     %rcx
    imul    $1000, 8(%rsp), %rcx
    add     %rcx, %rax
    mov     (%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
    UNFRAME 32
END_FUNCTION lantern_shell_time_ms

# (path, mode, result): docs/reference/shell.md. rbx the flags. Locals: L result, L+16 the path.
FUNCTION lantern_shell_open
    ENTER SHELL_PATH_FRAME
    mov     %rdx, L(%rsp)
    movq    $0, (%rdx)
    movq    $0, 8(%rdx)
    mov     (%rsi), %rax
    mov     $OS_O_RDONLY_CLOEXEC, %ebx
    cmp     $2, %rax
    ja      92f
    jb      3f
    mov     $OS_O_RDWR_CREATE, %ebx
    jmp     1f
3:  test    %rax, %rax
    jz      1f
    mov     $OS_O_APPEND_CREATE, %ebx
1:  mov     %rdi, %rax
    CPATH   (L + 16), 91f
2:  mov     $OS_AT_FDCWD, %rdi
    lea     (L + 16)(%rsp), %rsi
    mov     %rbx, %rdx
    mov     $OS_MODE_FILE, %r10d
    SYSCALL SYS_OPENAT
    cmp     $-OS_EINTR, %rax
    je      2b
    cmp     $-4095, %rax
    jae     90f
    mov     L(%rsp), %rcx
    mov     %rax, 8(%rcx)
    xor     %eax, %eax
    LEAVE SHELL_PATH_FRAME
92: mov     $-OS_EINVAL, %rax
    jmp     90f
91: mov     $-OS_ENAMETOOLONG, %rax
90: SHELL_ERROR SHELL_PATH_FRAME
END_FUNCTION lantern_shell_open

# (file, bytes, result): docs/reference/shell.md. r8 result, its value the bytes written; r9 the file, r10 the bytes. Locals: 0 their count.
FUNCTION lantern_shell_append
    FRAME 16
    mov     %rdx, %r8
    movq    $0, (%r8)
    movq    $0, 8(%r8)
    mov     (%rdi), %r9
    mov     8(%rsi), %r10
    add     %rsi, %r10
    mov     16(%rsi), %rax
    mov     %rax, (%rsp)
1:  mov     8(%r8), %rsi
    cmp     (%rsp), %rsi
    jae     9f
    mov     %r9, %rdi
    mov     (%rsp), %rdx
    sub     %rsi, %rdx
    add     %r10, %rsi
    SYSCALL SYS_WRITE
    cmp     $-OS_EINTR, %rax
    je      1b
    cmp     $-4095, %rax
    jae     8f
    test    %rax, %rax
    jz      7f
    add     %rax, 8(%r8)
    jmp     1b
7:  mov     $-OS_EIO, %rax                  # no progress
8:  neg     %rax
    mov     %rax, (%r8)
9:  xor     %eax, %eax
    UNFRAME 16
END_FUNCTION lantern_shell_append

# (file, offset, bytes, result): docs/reference/shell.md. r8 result, its value the bytes written; r9 the file.
# Locals: 0 the count of the bytes, 8 their address, 16 the offset.
FUNCTION lantern_shell_write_at
    FRAME 32
    mov     %rcx, %r8
    movq    $0, (%r8)
    movq    $0, 8(%r8)
    mov     (%rdi), %r9
    mov     (%rsi), %rax
    mov     %rax, 16(%rsp)
    mov     8(%rdx), %rax
    add     %rdx, %rax
    mov     %rax, 8(%rsp)
    mov     16(%rdx), %rax
    mov     %rax, (%rsp)
1:  mov     8(%r8), %rsi                    # the bytes written so far
    cmp     (%rsp), %rsi
    jae     9f
    mov     %r9, %rdi
    mov     (%rsp), %rdx
    sub     %rsi, %rdx
    mov     16(%rsp), %r10                  # at the offset + those bytes
    add     %rsi, %r10
    add     8(%rsp), %rsi
    SYSCALL SYS_PWRITE64
    cmp     $-OS_EINTR, %rax
    je      1b
    cmp     $-4095, %rax
    jae     8f
    test    %rax, %rax
    jz      7f
    add     %rax, 8(%r8)
    jmp     1b
7:  mov     $-OS_EIO, %rax                  # no progress
8:  neg     %rax
    mov     %rax, (%r8)
9:  xor     %eax, %eax
    UNFRAME 32
END_FUNCTION lantern_shell_write_at

# (file, result): docs/reference/shell.md. r8 result, r9 the file.
FUNCTION lantern_shell_sync
    UNWIND_END_PROLOGUE
    mov     %rsi, %r8
    movq    $0, (%r8)
    movq    $0, 8(%r8)
    mov     (%rdi), %r9
1:  mov     %r9, %rdi
    SYSCALL SYS_FDATASYNC
    cmp     $-OS_EINTR, %rax
    je      1b
    cmp     $-4095, %rax
    jb      9f
    neg     %rax
    mov     %rax, (%r8)
9:  xor     %eax, %eax
    ret
END_FUNCTION lantern_shell_sync

# (file, size, result): docs/reference/shell.md. r8 result, r9 the file, r10 the size.
FUNCTION lantern_shell_truncate
    UNWIND_END_PROLOGUE
    mov     %rdx, %r8
    movq    $0, (%r8)
    movq    $0, 8(%r8)
    mov     (%rdi), %r9
    mov     (%rsi), %r10
1:  mov     %r9, %rdi
    mov     %r10, %rsi
    SYSCALL SYS_FTRUNCATE
    cmp     $-OS_EINTR, %rax
    je      1b
    cmp     $-4095, %rax
    jb      9f
    neg     %rax
    mov     %rax, (%r8)
9:  xor     %eax, %eax
    ret
END_FUNCTION lantern_shell_truncate

# (file): docs/reference/shell.md.
FUNCTION lantern_shell_close
    UNWIND_END_PROLOGUE
    mov     (%rdi), %rdi
    SYSCALL SYS_CLOSE
    xor     %eax, %eax
    ret
END_FUNCTION lantern_shell_close

# (path, result): docs/reference/shell.md. Locals: L result, L+8 the file, L+16 the memory, L+24
# the size, L+40 an error, L+48 a struct stat, L+192 the path.
FUNCTION lantern_shell_map_file
    ENTER 4304
    mov     %rsi, L(%rsp)
    movq    $0, (%rsi)
    movq    $0, 8(%rsi)
    movq    $0, 16(%rsi)
    movq    $0, 24(%rsi)
    mov     %rdi, %rax
    CPATH   (L + 192), 91f
1:  mov     $OS_AT_FDCWD, %rdi
    lea     (L + 192)(%rsp), %rsi
    mov     $OS_O_RDONLY_CLOEXEC, %edx
    xor     %r10d, %r10d
    SYSCALL SYS_OPENAT
    cmp     $-OS_EINTR, %rax
    je      1b
    cmp     $-4095, %rax
    jae     90f
    mov     %rax, (L + 8)(%rsp)
    mov     %rax, %rdi                      # its size
    lea     (L + 48)(%rsp), %rsi
    SYSCALL SYS_FSTAT
    cmp     $-4095, %rax
    jae     80f
    mov     (L + 48 + OS_STAT_SIZE)(%rsp), %rsi
    mov     %rsi, (L + 24)(%rsp)
    test    %rsi, %rsi
    jz      85f                             # no bytes: address 0
    xor     %edi, %edi
    mov     $OS_PROT_READ, %edx
    mov     $OS_MAP_SHARED, %r10d
    mov     (L + 8)(%rsp), %r8
    xor     %r9d, %r9d
    SYSCALL SYS_MMAP
    cmp     $-4095, %rax
    jae     80f
    mov     %rax, (L + 16)(%rsp)
    mov     (L + 8)(%rsp), %rdi
    SYSCALL SYS_CLOSE
    mov     L(%rsp), %rcx
    mov     (L + 16)(%rsp), %rax
    mov     %rax, 8(%rcx)
    mov     (L + 24)(%rsp), %rax
    mov     %rax, 16(%rcx)
    mov     %rax, 24(%rcx)
    xor     %eax, %eax
    LEAVE 4304
85: mov     (L + 8)(%rsp), %rdi
    SYSCALL SYS_CLOSE
    xor     %eax, %eax
    LEAVE 4304
80: mov     %rax, (L + 40)(%rsp)            # the file closes
    mov     (L + 8)(%rsp), %rdi
    SYSCALL SYS_CLOSE
    mov     (L + 40)(%rsp), %rax
    jmp     90f
91: mov     $-OS_ENAMETOOLONG, %rax
90: SHELL_ERROR 4304
END_FUNCTION lantern_shell_map_file

# (address, size): docs/reference/shell.md.
FUNCTION lantern_shell_unmap_file
    UNWIND_END_PROLOGUE
    mov     (%rsi), %rsi
    mov     (%rdi), %rdi
    SYSCALL SYS_MUNMAP
    xor     %eax, %eax
    ret
END_FUNCTION lantern_shell_unmap_file

# (path, result): docs/reference/shell.md. Locals: L result, L+16 the path.
FUNCTION lantern_shell_remove
    ENTER SHELL_PATH_FRAME
    mov     %rsi, L(%rsp)
    movq    $0, (%rsi)
    movq    $0, 8(%rsi)
    mov     %rdi, %rax
    CPATH   (L + 16), 91f
1:  mov     $OS_AT_FDCWD, %rdi
    lea     (L + 16)(%rsp), %rsi
    xor     %edx, %edx
    SYSCALL SYS_UNLINKAT
    cmp     $-OS_EINTR, %rax
    je      1b
    cmp     $-4095, %rax
    jae     90f
    xor     %eax, %eax
    LEAVE SHELL_PATH_FRAME
91: mov     $-OS_ENAMETOOLONG, %rax
90: SHELL_ERROR SHELL_PATH_FRAME
END_FUNCTION lantern_shell_remove

# (from, to, result): docs/reference/shell.md. Locals: L result, L+8 to, L+16 from's path, L+4112 to's.
FUNCTION lantern_shell_rename
    ENTER SHELL_TWO_PATHS
    mov     %rdx, L(%rsp)
    movq    $0, (%rdx)
    movq    $0, 8(%rdx)
    mov     %rsi, (L + 8)(%rsp)
    mov     %rdi, %rax
    CPATH   (L + 16), 91f
    mov     (L + 8)(%rsp), %rax
    CPATH   (L + 4112), 91f
1:  mov     $OS_AT_FDCWD, %rdi
    lea     (L + 16)(%rsp), %rsi
    mov     $OS_AT_FDCWD, %rdx
    lea     (L + 4112)(%rsp), %r10
    xor     %r8d, %r8d
    SYSCALL SYS_RENAMEAT2
    cmp     $-OS_EINTR, %rax
    je      1b
    cmp     $-4095, %rax
    jae     90f
    xor     %eax, %eax
    LEAVE SHELL_TWO_PATHS
91: mov     $-OS_ENAMETOOLONG, %rax
90: SHELL_ERROR SHELL_TWO_PATHS
END_FUNCTION lantern_shell_rename

# (path, result): docs/reference/shell.md. Locals: L result, L+16 the path.
FUNCTION lantern_shell_mkdir
    ENTER SHELL_PATH_FRAME
    mov     %rsi, L(%rsp)
    movq    $0, (%rsi)
    movq    $0, 8(%rsi)
    mov     %rdi, %rax
    CPATH   (L + 16), 91f
1:  mov     $OS_AT_FDCWD, %rdi
    lea     (L + 16)(%rsp), %rsi
    mov     $OS_MODE_DIR, %edx
    SYSCALL SYS_MKDIRAT
    cmp     $-OS_EINTR, %rax
    je      1b
    cmp     $-4095, %rax
    jae     90f
    xor     %eax, %eax
    LEAVE SHELL_PATH_FRAME
91: mov     $-OS_ENAMETOOLONG, %rax
90: SHELL_ERROR SHELL_PATH_FRAME
END_FUNCTION lantern_shell_mkdir

# (path, result): docs/reference/shell.md. rbx the directory, rbp an error. Locals: L result, L+16 the path.
FUNCTION lantern_shell_sync_dir
    ENTER SHELL_PATH_FRAME
    mov     %rsi, L(%rsp)
    movq    $0, (%rsi)
    movq    $0, 8(%rsi)
    mov     %rdi, %rax
    CPATH   (L + 16), 91f
1:  mov     $OS_AT_FDCWD, %rdi
    lea     (L + 16)(%rsp), %rsi
    mov     $OS_O_RDONLY_CLOEXEC, %edx
    xor     %r10d, %r10d
    SYSCALL SYS_OPENAT
    cmp     $-OS_EINTR, %rax
    je      1b
    cmp     $-4095, %rax
    jae     90f
    mov     %rax, %rbx
2:  mov     %rbx, %rdi
    SYSCALL SYS_FSYNC
    cmp     $-OS_EINTR, %rax
    je      2b
    mov     %rax, %rbp
    mov     %rbx, %rdi
    SYSCALL SYS_CLOSE
    mov     %rbp, %rax
    cmp     $-4095, %rax
    jae     90f
    xor     %eax, %eax
    LEAVE SHELL_PATH_FRAME
91: mov     $-OS_ENAMETOOLONG, %rax
90: SHELL_ERROR SHELL_PATH_FRAME
END_FUNCTION lantern_shell_sync_dir

.set SYS_GETRUSAGE, 98
.set SYS_PRLIMIT64, 302

/* (out): docs/reference/shell.md. Locals: struct rusage (144 bytes), struct rlimit (16), then out. */
FUNCTION lantern_shell_process
    FRAME 176
    mov     %rdi, 160(%rsp)
    xor     %edi, %edi                      # getrusage(RUSAGE_SELF)
    mov     %rsp, %rsi
    SYSCALL SYS_GETRUSAGE
    mov     (%rsp), %rax                    # user and system seconds, then their microseconds
    add     16(%rsp), %rax
    imul    $1000000, %rax, %rax
    add     8(%rsp), %rax
    add     24(%rsp), %rax
    mov     160(%rsp), %rcx
    mov     %rax, (%rcx)
    mov     32(%rsp), %rax                  # ru_maxrss, in KiB
    shl     $10, %rax
    mov     %rax, 8(%rcx)
    xor     %edi, %edi                      # prlimit64(0, RLIMIT_NOFILE, NULL, &old)
    mov     $7, %esi
    xor     %edx, %edx
    lea     144(%rsp), %r10
    SYSCALL SYS_PRLIMIT64
    xor     %edx, %edx
    test    %rax, %rax
    jnz     1f
    mov     144(%rsp), %rdx
1:  mov     160(%rsp), %rcx
    mov     %rdx, 16(%rcx)
    xor     %eax, %eax
    UNFRAME 176
END_FUNCTION lantern_shell_process

# ---------------------------------------------------------------- the pool

.set SYS_FUTEX, 202
.set SYS_CLONE, 56
.set SYS_EXIT, 60
.set SYS_MPROTECT, 10
.set OS_FUTEX_WAIT, 0                       # shared: CLONE_CHILD_CLEARTID wakes the thread ID word so
.set OS_FUTEX_WAIT_PRIVATE, 128
.set OS_FUTEX_WAKE_PRIVATE, 129
.set OS_CLONE_THREAD, 0x350f00              # VM, FS, FILES, SIGHAND, THREAD, SYSVSEM, PARENT_SETTID, CHILD_CLEARTID
.set OS_PROT_NONE, 0
.set PoolThread_tid, 0                      # u32: the thread's ID, 0 once it has ended
.set PoolThread_stack, 8
.set PoolThread__mem, 16

# (pool, threads, result): docs/reference/shell.md. rbx pool, rbp the workers to start, r12 result,
# r13 the next worker, r14 its PoolThread.
FUNCTION lantern_shell_pool_start
    ENTER 0
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    movq    $0, (%r12)
    movq    $0, 8(%r12)
    mov     $1, %eax                        # 1 to SHELL_POOL_MAX threads, the caller included
    test    %rbp, %rbp
    cmovz   %rax, %rbp
    mov     $SHELL_POOL_MAX, %eax
    cmp     %rax, %rbp
    cmova   %rax, %rbp
    dec     %rbp
    movq    $0, ShellPool_workers(%rbx)
    xor     %r13d, %r13d
1:  cmp     %rbp, %r13
    jae     9f
    xor     %edi, %edi                      # its stack, the lowest page a guard
    mov     $SHELL_POOL_STACK, %esi
    mov     $OS_PROT_RW, %edx
    mov     $OS_MAP_PRIVATE_ANON, %r10d
    mov     $-1, %r8
    xor     %r9d, %r9d
    SYSCALL SYS_MMAP
    cmp     $-4095, %rax
    jae     8f
    mov     %r13, %r14
    shl     $4, %r14
    lea     ShellPool_os(%rbx,%r14), %r14
    mov     %rax, PoolThread_stack(%r14)
    mov     %rax, %rdi
    mov     $4096, %esi
    mov     $OS_PROT_NONE, %edx
    SYSCALL SYS_MPROTECT
    mov     PoolThread_stack(%r14), %rsi    # the pool at the stack's top for the thread
    add     $(SHELL_POOL_STACK - 16), %rsi
    mov     %rbx, (%rsi)
    mov     $OS_CLONE_THREAD, %edi
    lea     PoolThread_tid(%r14), %rdx
    lea     PoolThread_tid(%r14), %r10
    xor     %r8d, %r8d
    SYSCALL SYS_CLONE
    test    %rax, %rax
    jz      5f
    cmp     $-4095, %rax
    jae     7f
    inc     %r13
    mov     %r13, ShellPool_workers(%rbx)
    jmp     1b
5:  mov     (%rsp), %rdi                    # the new thread, on its own stack
    jmp     lantern_shell_pool_worker
7:  mov     %rax, %r15                      # no thread: its stack goes back
    mov     PoolThread_stack(%r14), %rdi
    mov     $SHELL_POOL_STACK, %esi
    SYSCALL SYS_MUNMAP
    mov     %r15, %rax
8:  neg     %rax
    mov     %rax, (%r12)
9:  mov     %r13, 8(%r12)
    xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_pool_start

# The jobs of the run of pool rdi until none is left. rbx pool.
LOCAL_FUNCTION lantern_shell_pool_jobs
    ENTER 0
    mov     %rdi, %rbx
1:  mov     $1, %esi                        # the next index
    lock xadd %rsi, ShellPool_next(%rbx)
    cmp     ShellPool_count(%rbx), %rsi
    jae     9f
    mov     ShellPool_context(%rbx), %rdi
    call    *ShellPool_function(%rbx)
    jmp     1b
9:  LEAVE 0
END_FUNCTION lantern_shell_pool_jobs

# A worker of pool rdi: each new generation's jobs, then its done count; it ends at stop. rbx pool, ebp the generation.
LOCAL_FUNCTION lantern_shell_pool_worker
    UNWIND_END_PROLOGUE
    mov     %rdi, %rbx
    xor     %ebp, %ebp
1:  mov     ShellPool_gen(%rbx), %eax       # an aligned load: acquire
    cmp     %ebp, %eax
    jne     2f
    lea     ShellPool_gen(%rbx), %rdi       # wait while it is the same
    mov     $OS_FUTEX_WAIT_PRIVATE, %esi
    mov     %ebp, %edx
    xor     %r10d, %r10d
    SYSCALL SYS_FUTEX
    jmp     1b
2:  mov     %eax, %ebp
    cmpq    $0, ShellPool_stop(%rbx)
    jne     9f
    mov     %rbx, %rdi
    call    lantern_shell_pool_jobs
    mov     $1, %eax                        # done: a locked add, after the jobs' bytes
    lock xadd %eax, ShellPool_done(%rbx)
    inc     %eax
    cmp     ShellPool_workers(%rbx), %rax
    jne     1b
    lea     ShellPool_done(%rbx), %rdi      # the last one wakes the caller
    mov     $OS_FUTEX_WAKE_PRIVATE, %esi
    mov     $1, %edx
    SYSCALL SYS_FUTEX
    jmp     1b
9:  xor     %edi, %edi
    SYSCALL SYS_EXIT
    jmp     9b
END_FUNCTION lantern_shell_pool_worker

# (pool, job): docs/reference/shell.md. rbx pool, rbp 1 when the workers take part.
FUNCTION lantern_shell_pool_run
    ENTER 0
    mov     %rdi, %rbx
    mov     ShellJob_function(%rsi), %rax
    mov     %rax, ShellPool_function(%rbx)
    mov     ShellJob_context(%rsi), %rax
    mov     %rax, ShellPool_context(%rbx)
    mov     ShellJob_count(%rsi), %rcx
    mov     %rcx, ShellPool_count(%rbx)
    movq    $0, ShellPool_next(%rbx)
    xor     %ebp, %ebp
    cmpq    $0, ShellPool_workers(%rbx)     # no workers, or one job: the caller alone
    je      5f
    cmp     $2, %rcx
    jb      5f
    mov     $1, %ebp
    movl    $0, ShellPool_done(%rbx)
    incl    ShellPool_gen(%rbx)             # the next generation: a store after the job's
    lea     ShellPool_gen(%rbx), %rdi
    mov     $OS_FUTEX_WAKE_PRIVATE, %esi
    mov     $0x7fffffff, %edx
    SYSCALL SYS_FUTEX
5:  mov     %rbx, %rdi
    call    lantern_shell_pool_jobs
    test    %ebp, %ebp
    jz      9f
6:  mov     ShellPool_done(%rbx), %edx      # every worker done: a load before their jobs' bytes
    cmp     ShellPool_workers(%rbx), %rdx
    je      9f
    lea     ShellPool_done(%rbx), %rdi
    mov     $OS_FUTEX_WAIT_PRIVATE, %esi
    xor     %r10d, %r10d
    SYSCALL SYS_FUTEX
    jmp     6b
9:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_pool_run

# (pool): docs/reference/shell.md. rbx pool, rbp the next worker, r12 its PoolThread.
FUNCTION lantern_shell_pool_stop
    ENTER 0
    mov     %rdi, %rbx
    cmpq    $0, ShellPool_workers(%rbx)
    je      9f
    movq    $1, ShellPool_stop(%rbx)
    incl    ShellPool_gen(%rbx)             # a new generation that ends them
    lea     ShellPool_gen(%rbx), %rdi
    mov     $OS_FUTEX_WAKE_PRIVATE, %esi
    mov     $0x7fffffff, %edx
    SYSCALL SYS_FUTEX
    xor     %ebp, %ebp
1:  cmp     ShellPool_workers(%rbx), %rbp
    jae     8f
    mov     %rbp, %r12
    shl     $4, %r12
    lea     ShellPool_os(%rbx,%r12), %r12
2:  mov     PoolThread_tid(%r12), %edx      # joined: the kernel clears the ID when the thread has ended
    test    %edx, %edx
    jz      3f
    lea     PoolThread_tid(%r12), %rdi
    mov     $OS_FUTEX_WAIT, %esi
    xor     %r10d, %r10d
    SYSCALL SYS_FUTEX
    jmp     2b
3:  mov     PoolThread_stack(%r12), %rdi
    mov     $SHELL_POOL_STACK, %esi
    SYSCALL SYS_MUNMAP
    inc     %rbp
    jmp     1b
8:  movq    $0, ShellPool_workers(%rbx)
    movq    $0, ShellPool_stop(%rbx)
9:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_pool_stop
