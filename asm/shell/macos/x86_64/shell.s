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

/* rax = errno, after a libSystem call that gave -1. */
.macro OS_ERRNO
    CALL_GLOBAL __error
    movslq  (%rax), %rax
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
