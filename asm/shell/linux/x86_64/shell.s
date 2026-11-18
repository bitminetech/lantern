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
 * L+24 the file's size, L+32 the size mapped, L+40 the bytes read or an error, L+48 a struct
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
    test    %rsi, %rsi                      # memory of the size, at least 1 byte
    jnz     1f
    mov     $1, %esi
1:  mov     %rsi, (L + 32)(%rsp)
    xor     %edi, %edi
    mov     $OS_PROT_RW, %edx
    mov     $OS_MAP_PRIVATE_ANON, %r10d
    mov     $-1, %r8
    xor     %r9d, %r9d
    SYSCALL SYS_MMAP
    cmp     $-4095, %rax
    jae     80f
    mov     %rax, (L + 16)(%rsp)
    movq    $0, (L + 40)(%rsp)
2:  mov     (L + 40)(%rsp), %rsi            # every byte
    cmp     (L + 24)(%rsp), %rsi
    jae     3f
    mov     (L + 8)(%rsp), %rdi
    mov     (L + 24)(%rsp), %rdx
    sub     %rsi, %rdx
    add     (L + 16)(%rsp), %rsi
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
