/*
 * The shell of the lantern binary for macOS on x86-64: memory, files, the log and the clock,
 * through libSystem. Requirements: docs/reference/shell.md.
 *
 * The functions use the System V AMD64 convention and call libSystem with the same convention. A
 * libSystem call that fails gives -1, with the error number in errno (from __error()).
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
.set SHELL_TWO_PATHS, 8192                  /* rename: L from, L + 4096 to */

/* rax = errno, after a libSystem call that gave -1. */
.macro OS_ERRNO
    CALL_GLOBAL __error
    movslq  (%rax), %rax
.endm

/* The path ByteList at rax as a string with a zero after it at \at(%rsp); to \long when above SHELL_PATH_MAX bytes. Uses rcx, rsi, rdi. */
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

/* After a libSystem call that gives -1 on an error: on to \ok when eax is not -1; again at \again on EINTR; else rax = errno. */
.macro OS_CHECK ok, again
    cmp     $-1, %eax
    jne     \ok
    OS_ERRNO
    cmp     $OS_EINTR, %rax
    je      \again
.endm

/* (size, out): docs/reference/shell.md. rbx out. */
FUNCTION lantern_shell_map
    ENTER 0
    mov     %rsi, %rbx
    mov     (%rdi), %rsi
    xor     %edi, %edi
    mov     $OS_PROT_RW, %edx
    mov     $OS_MAP_PRIVATE_ANON, %ecx
    mov     $-1, %r8d
    xor     %r9d, %r9d
    CALL_GLOBAL mmap
    cmp     $-1, %rax                       # MAP_FAILED: 0
    jne     1f
    xor     %eax, %eax
1:  mov     %rax, (%rbx)
    xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_map

/* (address, size): docs/reference/shell.md. */
FUNCTION lantern_shell_unmap
    ENTER 0
    mov     (%rsi), %rsi
    mov     (%rdi), %rdi
    CALL_GLOBAL munmap
    xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_unmap

/*
 * (path, result): docs/reference/shell.md. rbx result, rbp the file, r12 the memory, r13 the
 * file's size, r14 the size mapped (24 more), r15 the bytes read or an error. Frame: the path
 * with a zero after it, at rsp.
 */
FUNCTION lantern_shell_read_file
    ENTER 0
    sub     $SHELL_READ_FRAME, %rsp
    mov     %rsi, %rbx
    movq    $0, (%rbx)
    movq    $0, 8(%rbx)
    movq    $0, 16(%rbx)
    movq    $0, 24(%rbx)
    mov     16(%rdi), %rdx                  # the path, with a zero after it
    cmp     $SHELL_PATH_MAX, %rdx
    ja      91f
    mov     8(%rdi), %rsi
    add     %rdi, %rsi
    xor     %ecx, %ecx
1:  cmp     %rdx, %rcx
    jae     2f
    movzbl  (%rsi,%rcx), %eax
    mov     %al, (%rsp,%rcx)
    inc     %rcx
    jmp     1b
2:  movb    $0, (%rsp,%rcx)
    mov     %rsp, %rdi
    mov     $OS_O_RDONLY_CLOEXEC, %esi
    xor     %eax, %eax                      # open is variadic: no vector arguments
    CALL_GLOBAL open
    cmp     $-1, %eax
    je      90f
    mov     %eax, %ebp
    mov     %ebp, %edi                      # its size: the end's offset, then back to the start
    xor     %esi, %esi
    mov     $OS_SEEK_END, %edx
    CALL_GLOBAL lseek
    cmp     $-1, %rax
    je      80f
    mov     %rax, %r13
    mov     %ebp, %edi
    xor     %esi, %esi
    mov     $OS_SEEK_SET, %edx
    CALL_GLOBAL lseek
    cmp     $-1, %rax
    je      80f
    lea     24(%r13), %r14                  # a ByteList: 24 bytes, then the file's
    xor     %edi, %edi
    mov     %r14, %rsi
    mov     $OS_PROT_RW, %edx
    mov     $OS_MAP_PRIVATE_ANON, %ecx
    mov     $-1, %r8d
    xor     %r9d, %r9d
    CALL_GLOBAL mmap
    cmp     $-1, %rax
    je      80f
    mov     %rax, %r12
    mov     %r14, (%r12)
    movq    $24, 8(%r12)
    mov     %r13, 16(%r12)
    xor     %r15d, %r15d
4:  cmp     %r13, %r15                      # every byte
    jae     5f
    mov     %ebp, %edi
    lea     24(%r12,%r15), %rsi
    mov     %r13, %rdx
    sub     %r15, %rdx
    CALL_GLOBAL read
    cmp     $-1, %rax
    jne     41f
    OS_ERRNO
    cmp     $OS_EINTR, %rax
    je      4b
    jmp     70f
41: test    %rax, %rax
    jz      71f
    add     %rax, %r15
    jmp     4b
5:  mov     %ebp, %edi
    CALL_GLOBAL close
    movq    $0, (%rbx)
    mov     %r12, 8(%rbx)
    mov     %r13, 16(%rbx)
    mov     %r14, 24(%rbx)
    jmp     99f
71: mov     $1, %eax                        # the file ends before its size: error 1
70: mov     %rax, %r15                      # the memory goes back
    mov     %r12, %rdi
    mov     %r14, %rsi
    CALL_GLOBAL munmap
    mov     %r15, %rax
    jmp     81f
80: OS_ERRNO                                # the file closes
81: mov     %rax, %r15
    mov     %ebp, %edi
    CALL_GLOBAL close
    mov     %r15, %rax
    jmp     92f
90: OS_ERRNO
92: mov     %rax, (%rbx)                    # the error
    jmp     99f
91: mov     $OS_ENAMETOOLONG, %eax
    jmp     92b
99: add     $SHELL_READ_FRAME, %rsp
    xor     %eax, %eax
    LEAVE 0
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
    mov     %ebx, %edi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    CALL_GLOBAL write
    cmp     $-1, %rax
    jne     2f
    OS_ERRNO
    cmp     $OS_EINTR, %rax
    je      1b
    jmp     9f
2:  add     %rax, %rbp
    sub     %rax, %r12
    jmp     1b
9:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_write

/* (out): docs/reference/shell.md. rbx out. */
FUNCTION lantern_shell_time_ms
    ENTER 0
    mov     %rdi, %rbx
    mov     $OS_CLOCK_REALTIME, %edi
    CALL_GLOBAL clock_gettime_nsec_np
    xor     %edx, %edx
    mov     $1000000, %ecx
    div     %rcx
    mov     %rax, (%rbx)
    xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_time_ms

/* (path, mode, result): docs/reference/shell.md. rbx result, ebp the flags. Locals: L the path. */
FUNCTION lantern_shell_open
    ENTER SHELL_READ_FRAME
    mov     %rdx, %rbx
    movq    $0, (%rbx)
    movq    $0, 8(%rbx)
    mov     (%rsi), %rax
    mov     $OS_O_RDONLY_CLOEXEC, %ebp
    cmp     $2, %rax
    ja      92f
    jb      4f
    mov     $OS_O_RDWR_CREATE, %ebp
    jmp     1f
4:  test    %rax, %rax
    jz      1f
    mov     $OS_O_APPEND_CREATE, %ebp
1:  mov     %rdi, %rax
    CPATH   L, 91f
2:  lea     L(%rsp), %rdi
    mov     %ebp, %esi
    mov     $OS_MODE_FILE, %edx
    xor     %eax, %eax                      # open is variadic: no vector arguments
    CALL_GLOBAL open
    OS_CHECK 3f, 2b
    jmp     90f
3:  mov     %eax, %eax
    mov     %rax, 8(%rbx)
    jmp     99f
92: mov     $OS_EINVAL, %eax
    jmp     90f
91: mov     $OS_ENAMETOOLONG, %eax
90: mov     %rax, (%rbx)
99: xor     %eax, %eax
    LEAVE SHELL_READ_FRAME
END_FUNCTION lantern_shell_open

/* (file, bytes, result): docs/reference/shell.md. rbx result, rbp the file, r12 the bytes, r13 their count, r14 written. */
FUNCTION lantern_shell_append
    ENTER 0
    mov     %rdx, %rbx
    movq    $0, (%rbx)
    movq    $0, 8(%rbx)
    mov     (%rdi), %rbp
    mov     8(%rsi), %r12
    add     %rsi, %r12
    mov     16(%rsi), %r13
    xor     %r14d, %r14d
1:  cmp     %r13, %r14
    jae     9f
    mov     %ebp, %edi
    lea     (%r12,%r14), %rsi
    mov     %r13, %rdx
    sub     %r14, %rdx
    mov     $SHELL_WRITE_MAX, %eax
    cmp     %rax, %rdx
    cmova   %rax, %rdx
    CALL_GLOBAL write
    OS_CHECK 2f, 1b
    jmp     8f
2:  test    %rax, %rax
    jz      7f
    add     %rax, %r14
    jmp     1b
7:  mov     $OS_EIO, %eax                   # no progress
8:  mov     %rax, (%rbx)
9:  mov     %r14, 8(%rbx)
    xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_append

/* (file, offset, bytes, result): docs/reference/shell.md. rbx result, rbp the file, r12 the bytes, r13 their count, r14 written, r15 the offset. */
FUNCTION lantern_shell_write_at
    ENTER 0
    mov     %rcx, %rbx
    movq    $0, (%rbx)
    movq    $0, 8(%rbx)
    mov     (%rdi), %rbp
    mov     (%rsi), %r15
    mov     8(%rdx), %r12
    add     %rdx, %r12
    mov     16(%rdx), %r13
    xor     %r14d, %r14d
1:  cmp     %r13, %r14
    jae     9f
    mov     %ebp, %edi
    lea     (%r12,%r14), %rsi
    mov     %r13, %rdx
    sub     %r14, %rdx
    mov     $SHELL_WRITE_MAX, %eax
    cmp     %rax, %rdx
    cmova   %rax, %rdx
    lea     (%r15,%r14), %rcx
    CALL_GLOBAL pwrite
    OS_CHECK 2f, 1b
    jmp     8f
2:  test    %rax, %rax
    jz      7f
    add     %rax, %r14
    jmp     1b
7:  mov     $OS_EIO, %eax                   # no progress
8:  mov     %rax, (%rbx)
9:  mov     %r14, 8(%rbx)
    xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_write_at

/* (file, result): docs/reference/shell.md. rbx result, ebp the file. */
FUNCTION lantern_shell_sync
    ENTER 0
    mov     %rsi, %rbx
    movq    $0, (%rbx)
    movq    $0, 8(%rbx)
    mov     (%rdi), %rbp
1:  mov     %ebp, %edi
    mov     $OS_F_FULLFSYNC, %esi
    xor     %eax, %eax                      # fcntl is variadic
    CALL_GLOBAL fcntl
    OS_CHECK 9f, 1b
2:  mov     %ebp, %edi                      # the file system does not support F_FULLFSYNC
    CALL_GLOBAL fsync
    OS_CHECK 9f, 2b
    mov     %rax, (%rbx)
9:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_sync

/* (file, size, result): docs/reference/shell.md. rbx result, ebp the file, r12 the size. */
FUNCTION lantern_shell_truncate
    ENTER 0
    mov     %rdx, %rbx
    movq    $0, (%rbx)
    movq    $0, 8(%rbx)
    mov     (%rdi), %rbp
    mov     (%rsi), %r12
1:  mov     %ebp, %edi
    mov     %r12, %rsi
    CALL_GLOBAL ftruncate
    OS_CHECK 9f, 1b
    mov     %rax, (%rbx)
9:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_truncate

/* (file): docs/reference/shell.md. */
FUNCTION lantern_shell_close
    ENTER 0
    mov     (%rdi), %rdi
    CALL_GLOBAL close
    xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_close

/* (path, result): docs/reference/shell.md. rbx result, ebp the file, r12 the size, r13 the memory or an error. Locals: L the path. */
FUNCTION lantern_shell_map_file
    ENTER SHELL_READ_FRAME
    mov     %rsi, %rbx
    movq    $0, (%rbx)
    movq    $0, 8(%rbx)
    movq    $0, 16(%rbx)
    movq    $0, 24(%rbx)
    mov     %rdi, %rax
    CPATH   L, 91f
1:  lea     L(%rsp), %rdi
    mov     $OS_O_RDONLY_CLOEXEC, %esi
    xor     %eax, %eax                      # open is variadic: no vector arguments
    CALL_GLOBAL open
    OS_CHECK 2f, 1b
    jmp     90f
2:  mov     %eax, %ebp
    mov     %ebp, %edi                      # its size: the end's offset
    xor     %esi, %esi
    mov     $OS_SEEK_END, %edx
    CALL_GLOBAL lseek
    cmp     $-1, %rax
    je      80f
    mov     %rax, %r12
    test    %r12, %r12
    jz      85f                             # no bytes: address 0
    xor     %edi, %edi
    mov     %r12, %rsi
    mov     $OS_PROT_READ, %edx
    mov     $OS_MAP_SHARED, %ecx
    mov     %ebp, %r8d
    xor     %r9d, %r9d
    CALL_GLOBAL mmap
    cmp     $-1, %rax
    je      80f
    mov     %rax, %r13
    mov     %ebp, %edi
    CALL_GLOBAL close
    mov     %r13, 8(%rbx)
    mov     %r12, 16(%rbx)
    mov     %r12, 24(%rbx)
    jmp     99f
85: mov     %ebp, %edi
    CALL_GLOBAL close
    jmp     99f
80: OS_ERRNO                                # the file closes
    mov     %rax, %r13
    mov     %ebp, %edi
    CALL_GLOBAL close
    mov     %r13, %rax
    jmp     90f
91: mov     $OS_ENAMETOOLONG, %eax
90: mov     %rax, (%rbx)
99: xor     %eax, %eax
    LEAVE SHELL_READ_FRAME
END_FUNCTION lantern_shell_map_file

/* (address, size): docs/reference/shell.md. */
FUNCTION lantern_shell_unmap_file
    ENTER 0
    mov     (%rsi), %rsi
    mov     (%rdi), %rdi
    CALL_GLOBAL munmap
    xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_unmap_file

/* (path, result): docs/reference/shell.md. rbx result. Locals: L the path. */
FUNCTION lantern_shell_remove
    ENTER SHELL_READ_FRAME
    mov     %rsi, %rbx
    movq    $0, (%rbx)
    movq    $0, 8(%rbx)
    mov     %rdi, %rax
    CPATH   L, 91f
1:  lea     L(%rsp), %rdi
    CALL_GLOBAL unlink
    OS_CHECK 99f, 1b
    jmp     90f
91: mov     $OS_ENAMETOOLONG, %eax
90: mov     %rax, (%rbx)
99: xor     %eax, %eax
    LEAVE SHELL_READ_FRAME
END_FUNCTION lantern_shell_remove

/* (from, to, result): docs/reference/shell.md. rbx result, rbp to. Locals: L from, L + 4096 to. */
FUNCTION lantern_shell_rename
    ENTER SHELL_TWO_PATHS
    mov     %rdx, %rbx
    movq    $0, (%rbx)
    movq    $0, 8(%rbx)
    mov     %rsi, %rbp
    mov     %rdi, %rax
    CPATH   L, 91f
    mov     %rbp, %rax
    CPATH   (L + SHELL_READ_FRAME), 91f
1:  lea     L(%rsp), %rdi
    lea     (L + SHELL_READ_FRAME)(%rsp), %rsi
    CALL_GLOBAL rename
    OS_CHECK 99f, 1b
    jmp     90f
91: mov     $OS_ENAMETOOLONG, %eax
90: mov     %rax, (%rbx)
99: xor     %eax, %eax
    LEAVE SHELL_TWO_PATHS
END_FUNCTION lantern_shell_rename

/* (path, result): docs/reference/shell.md. rbx result. Locals: L the path. */
FUNCTION lantern_shell_mkdir
    ENTER SHELL_READ_FRAME
    mov     %rsi, %rbx
    movq    $0, (%rbx)
    movq    $0, 8(%rbx)
    mov     %rdi, %rax
    CPATH   L, 91f
1:  lea     L(%rsp), %rdi
    mov     $OS_MODE_DIR, %esi
    CALL_GLOBAL mkdir
    OS_CHECK 99f, 1b
    jmp     90f
91: mov     $OS_ENAMETOOLONG, %eax
90: mov     %rax, (%rbx)
99: xor     %eax, %eax
    LEAVE SHELL_READ_FRAME
END_FUNCTION lantern_shell_mkdir

/* (path, result): docs/reference/shell.md. rbx result, ebp the directory, r12 an error. Locals: L the path. */
FUNCTION lantern_shell_sync_dir
    ENTER SHELL_READ_FRAME
    mov     %rsi, %rbx
    movq    $0, (%rbx)
    movq    $0, 8(%rbx)
    mov     %rdi, %rax
    CPATH   L, 91f
1:  lea     L(%rsp), %rdi
    mov     $OS_O_RDONLY_CLOEXEC, %esi
    xor     %eax, %eax                      # open is variadic: no vector arguments
    CALL_GLOBAL open
    OS_CHECK 2f, 1b
    jmp     90f
2:  mov     %eax, %ebp
    xor     %r12d, %r12d
3:  mov     %ebp, %edi
    CALL_GLOBAL fsync
    OS_CHECK 4f, 3b
    mov     %rax, %r12
4:  mov     %ebp, %edi
    CALL_GLOBAL close
    mov     %r12, (%rbx)
    jmp     99f
91: mov     $OS_ENAMETOOLONG, %eax
90: mov     %rax, (%rbx)
99: xor     %eax, %eax
    LEAVE SHELL_READ_FRAME
END_FUNCTION lantern_shell_sync_dir

/* (out): docs/reference/shell.md. rbx out. Locals: struct rusage (144 bytes), then struct rlimit (16). */
FUNCTION lantern_shell_process
    ENTER 160
    mov     %rdi, %rbx
    xor     %edi, %edi                      # getrusage(RUSAGE_SELF)
    lea     L(%rsp), %rsi
    CALL_GLOBAL getrusage
    mov     L(%rsp), %rax                   # user and system seconds; their microseconds are ints
    add     (L + 16)(%rsp), %rax
    imul    $1000000, %rax, %rax
    movslq  (L + 8)(%rsp), %rcx
    add     %rcx, %rax
    movslq  (L + 24)(%rsp), %rcx
    add     %rcx, %rax
    mov     %rax, (%rbx)
    mov     (L + 32)(%rsp), %rax            # ru_maxrss, in bytes
    mov     %rax, 8(%rbx)
    mov     $8, %edi                        # getrlimit(RLIMIT_NOFILE)
    lea     (L + 144)(%rsp), %rsi
    CALL_GLOBAL getrlimit
    xor     %ecx, %ecx
    test    %eax, %eax
    jnz     1f
    mov     (L + 144)(%rsp), %rcx
1:  mov     %rcx, 16(%rbx)
    xor     %eax, %eax
    LEAVE 160
END_FUNCTION lantern_shell_process

# ---------------------------------------------------------------- the pool

.set PoolMac_mutex, ShellPool_os            # pthread_mutex_t, 64 bytes
.set PoolMac_gen, ShellPool_os + 64         # pthread_cond_t of a new generation, 48 bytes
.set PoolMac_done, ShellPool_os + 112       # pthread_cond_t of the last worker done
.set PoolMac_threads, ShellPool_os + 160    # a pthread_t for each worker

# (pool, threads, result): docs/reference/shell.md. rbx pool, rbp the workers to start, r12 result, r13 the next worker.
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
    test    %rbp, %rbp
    jz      9f
    lea     PoolMac_mutex(%rbx), %rdi
    xor     %esi, %esi
    CALL_GLOBAL pthread_mutex_init
    test    %eax, %eax
    jnz     8f
    lea     PoolMac_gen(%rbx), %rdi
    xor     %esi, %esi
    CALL_GLOBAL pthread_cond_init
    test    %eax, %eax
    jnz     8f
    lea     PoolMac_done(%rbx), %rdi
    xor     %esi, %esi
    CALL_GLOBAL pthread_cond_init
    test    %eax, %eax
    jnz     8f
1:  cmp     %rbp, %r13
    jae     9f
    lea     PoolMac_threads(%rbx,%r13,8), %rdi
    xor     %esi, %esi
    lea     lantern_shell_pool_worker(%rip), %rdx
    mov     %rbx, %rcx
    CALL_GLOBAL pthread_create
    test    %eax, %eax
    jnz     8f
    inc     %r13
    mov     %r13, ShellPool_workers(%rbx)
    jmp     1b
8:  mov     %eax, %eax                      # pthread gives the error number
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

# A worker of pool rdi, the start routine of pthread_create: each new generation's jobs, then its
# done count, under the mutex; it returns at stop. rbx pool, ebp the generation, r12 the mutex, r13 stop.
LOCAL_FUNCTION lantern_shell_pool_worker
    ENTER 0
    mov     %rdi, %rbx
    xor     %ebp, %ebp
    lea     PoolMac_mutex(%rbx), %r12
1:  mov     %r12, %rdi
    CALL_GLOBAL pthread_mutex_lock
2:  mov     ShellPool_gen(%rbx), %eax       # wait while it is the same
    cmp     %ebp, %eax
    jne     3f
    lea     PoolMac_gen(%rbx), %rdi
    mov     %r12, %rsi
    CALL_GLOBAL pthread_cond_wait
    jmp     2b
3:  mov     %eax, %ebp
    mov     ShellPool_stop(%rbx), %r13
    mov     %r12, %rdi
    CALL_GLOBAL pthread_mutex_unlock
    test    %r13, %r13
    jnz     9f
    mov     %rbx, %rdi
    call    lantern_shell_pool_jobs
    mov     %r12, %rdi
    CALL_GLOBAL pthread_mutex_lock
    mov     ShellPool_done(%rbx), %eax
    inc     %eax
    mov     %eax, ShellPool_done(%rbx)
    cmp     ShellPool_workers(%rbx), %rax
    jne     4f
    lea     PoolMac_done(%rbx), %rdi        # the last one wakes the caller
    CALL_GLOBAL pthread_cond_signal
4:  mov     %r12, %rdi
    CALL_GLOBAL pthread_mutex_unlock
    jmp     1b
9:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_pool_worker

# (pool, job): docs/reference/shell.md. rbx pool, rbp 1 when the workers take part, r12 the mutex.
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
    lea     PoolMac_mutex(%rbx), %r12
    cmpq    $0, ShellPool_workers(%rbx)     # no workers, or one job: the caller alone
    je      5f
    cmp     $2, %rcx
    jb      5f
    mov     $1, %ebp
    mov     %r12, %rdi                      # the next generation, under the mutex
    CALL_GLOBAL pthread_mutex_lock
    movl    $0, ShellPool_done(%rbx)
    incl    ShellPool_gen(%rbx)
    lea     PoolMac_gen(%rbx), %rdi
    CALL_GLOBAL pthread_cond_broadcast
    mov     %r12, %rdi
    CALL_GLOBAL pthread_mutex_unlock
5:  mov     %rbx, %rdi
    call    lantern_shell_pool_jobs
    test    %ebp, %ebp
    jz      9f
    mov     %r12, %rdi                      # every worker done, under the mutex
    CALL_GLOBAL pthread_mutex_lock
6:  mov     ShellPool_done(%rbx), %eax
    cmp     ShellPool_workers(%rbx), %rax
    je      7f
    lea     PoolMac_done(%rbx), %rdi
    mov     %r12, %rsi
    CALL_GLOBAL pthread_cond_wait
    jmp     6b
7:  mov     %r12, %rdi
    CALL_GLOBAL pthread_mutex_unlock
9:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_pool_run

# (pool): docs/reference/shell.md. rbx pool, rbp the next worker, r12 the mutex.
FUNCTION lantern_shell_pool_stop
    ENTER 0
    mov     %rdi, %rbx
    cmpq    $0, ShellPool_workers(%rbx)
    je      9f
    lea     PoolMac_mutex(%rbx), %r12
    mov     %r12, %rdi                      # a new generation that ends them
    CALL_GLOBAL pthread_mutex_lock
    movq    $1, ShellPool_stop(%rbx)
    incl    ShellPool_gen(%rbx)
    lea     PoolMac_gen(%rbx), %rdi
    CALL_GLOBAL pthread_cond_broadcast
    mov     %r12, %rdi
    CALL_GLOBAL pthread_mutex_unlock
    xor     %ebp, %ebp
1:  cmp     ShellPool_workers(%rbx), %rbp
    jae     8f
    mov     PoolMac_threads(%rbx,%rbp,8), %rdi
    xor     %esi, %esi
    CALL_GLOBAL pthread_join
    inc     %rbp
    jmp     1b
8:  lea     PoolMac_done(%rbx), %rdi
    CALL_GLOBAL pthread_cond_destroy
    lea     PoolMac_gen(%rbx), %rdi
    CALL_GLOBAL pthread_cond_destroy
    mov     %r12, %rdi
    CALL_GLOBAL pthread_mutex_destroy
    movq    $0, ShellPool_workers(%rbx)
    movq    $0, ShellPool_stop(%rbx)
9:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_pool_stop
