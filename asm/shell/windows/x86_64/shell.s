/*
 * The shell of the lantern binary for Windows on x86-64: memory, files, the log and the clock,
 * through kernel32. AT&T syntax. Requirements: docs/reference/shell.md.
 *
 * The functions use the System V AMD64 psABI like the core, and call the Windows APIs with the
 * Windows x64 convention: arguments in rcx, rdx, r8, r9, then on the stack after 32 bytes of
 * shadow space. Those APIs keep rbx, rbp, rdi, rsi and r12-r15, so they keep what System V
 * callers need. The frame of ENTER gives the shadow space at rsp; the fifth to eighth arguments
 * of a call go at L to L+24.
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

/* Windows numbers: the llvm-mingw headers. */
.set OS_MEM_COMMIT_RESERVE, 0x3000          /* MEM_COMMIT | MEM_RESERVE, winnt.h */
.set OS_MEM_RELEASE, 0x8000                 /* winnt.h */
.set OS_PAGE_READWRITE, 4                   /* winnt.h */
.set OS_GENERIC_READ, 0x80000000            /* winnt.h */
.set OS_FILE_SHARE_READ, 1                  /* winnt.h */
.set OS_OPEN_EXISTING, 3                    /* fileapi.h */
.set OS_FILE_ATTRIBUTE_NORMAL, 0x80         /* winnt.h */
.set OS_CP_UTF8, 65001                      /* winnls.h */
.set OS_STD_OUTPUT_HANDLE, -11              /* processenv.h */
.set OS_STD_ERROR_HANDLE, -12
.set OS_ERROR_FILENAME_EXCED_RANGE, 206     /* winerror.h */
.set OS_UNIX_EPOCH, 116444736000000000      /* 100 ns ticks from 1601-01-01 to 1970-01-01 */
.set SHELL_PATH_MAX, 4095
.set SHELL_WIDE_BYTES, 8192                 /* read_file: the path in UTF-16, with a zero after it */
.set SHELL_IO_MAX, 1 << 30                  /* the bytes of one ReadFile or WriteFile */

/* (size, out): docs/reference/shell.md. rbx out. */
FUNCTION lantern_shell_map
    ENTER 0
    mov     %rsi, %rbx
    xor     %ecx, %ecx
    mov     (%rdi), %rdx
    mov     $OS_MEM_COMMIT_RESERVE, %r8d
    mov     $OS_PAGE_READWRITE, %r9d
    CALL_GLOBAL VirtualAlloc
    mov     %rax, (%rbx)
    xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_map

/* (address, size): docs/reference/shell.md. */
FUNCTION lantern_shell_unmap
    ENTER 0
    mov     (%rdi), %rcx
    xor     %edx, %edx
    mov     $OS_MEM_RELEASE, %r8d
    CALL_GLOBAL VirtualFree
    xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_shell_unmap

/*
 * (path, result): docs/reference/shell.md. rbx result, rbp the path then the file, r12 the
 * memory, r13 the file's size, r14 the size mapped (24 more), r15 the bytes read or an error.
 * Locals: L the stack arguments of a call, L+32 the wide path's memory, L+40 a count, L+48 the size.
 */
FUNCTION lantern_shell_read_file
    ENTER 64
    mov     %rsi, %rbx
    movq    $0, (%rbx)
    movq    $0, 8(%rbx)
    movq    $0, 16(%rbx)
    movq    $0, 24(%rbx)
    mov     %rdi, %rbp
    cmpq    $SHELL_PATH_MAX, 16(%rbp)
    ja      91f
    xor     %ecx, %ecx                      # the path in UTF-16, with a zero after it
    mov     $SHELL_WIDE_BYTES, %edx
    mov     $OS_MEM_COMMIT_RESERVE, %r8d
    mov     $OS_PAGE_READWRITE, %r9d
    CALL_GLOBAL VirtualAlloc
    test    %rax, %rax
    jz      90f
    mov     %rax, (L + 32)(%rsp)
    mov     $OS_CP_UTF8, %ecx
    xor     %edx, %edx
    mov     8(%rbp), %r8
    add     %rbp, %r8
    mov     16(%rbp), %r9
    mov     %rax, L(%rsp)
    movq    $(SHELL_WIDE_BYTES / 2 - 1), (L + 8)(%rsp)
    CALL_GLOBAL MultiByteToWideChar
    test    %eax, %eax
    jz      85f
    mov     (L + 32)(%rsp), %rcx            # open it
    mov     $OS_GENERIC_READ, %edx
    mov     $OS_FILE_SHARE_READ, %r8d
    xor     %r9d, %r9d
    movq    $OS_OPEN_EXISTING, L(%rsp)
    movq    $OS_FILE_ATTRIBUTE_NORMAL, (L + 8)(%rsp)
    movq    $0, (L + 16)(%rsp)
    CALL_GLOBAL CreateFileW
    cmp     $-1, %rax
    je      85f
    mov     %rax, %rbp
    mov     (L + 32)(%rsp), %rcx
    xor     %edx, %edx
    mov     $OS_MEM_RELEASE, %r8d
    CALL_GLOBAL VirtualFree
    mov     %rbp, %rcx                      # its size
    lea     (L + 48)(%rsp), %rdx
    CALL_GLOBAL GetFileSizeEx
    test    %eax, %eax
    jz      80f
    mov     (L + 48)(%rsp), %r13
    lea     24(%r13), %r14                  # a ByteList: 24 bytes, then the file's
    xor     %ecx, %ecx
    mov     %r14, %rdx
    mov     $OS_MEM_COMMIT_RESERVE, %r8d
    mov     $OS_PAGE_READWRITE, %r9d
    CALL_GLOBAL VirtualAlloc
    test    %rax, %rax
    jz      80f
    mov     %rax, %r12
    mov     %r14, (%r12)
    movq    $24, 8(%r12)
    mov     %r13, 16(%r12)
    xor     %r15d, %r15d
4:  cmp     %r13, %r15                      # every byte
    jae     5f
    mov     %rbp, %rcx
    lea     24(%r12,%r15), %rdx
    mov     %r13, %r8
    sub     %r15, %r8
    mov     $SHELL_IO_MAX, %eax
    cmp     %rax, %r8
    jbe     41f
    mov     %rax, %r8
41: movq    $0, (L + 40)(%rsp)
    lea     (L + 40)(%rsp), %r9
    movq    $0, L(%rsp)
    CALL_GLOBAL ReadFile
    test    %eax, %eax
    jz      70f
    mov     (L + 40)(%rsp), %eax
    test    %rax, %rax
    jz      71f
    add     %rax, %r15
    jmp     4b
5:  mov     %rbp, %rcx
    CALL_GLOBAL CloseHandle
    movq    $0, (%rbx)
    mov     %r12, 8(%rbx)
    mov     %r13, 16(%rbx)
    mov     %r14, 24(%rbx)
    jmp     99f
70: CALL_GLOBAL GetLastError
    mov     %eax, %eax
    jmp     72f
71: mov     $1, %eax                        # the file ends before its size: error 1
72: mov     %rax, %r15                      # the memory goes back
    mov     %r12, %rcx
    xor     %edx, %edx
    mov     $OS_MEM_RELEASE, %r8d
    CALL_GLOBAL VirtualFree
    mov     %r15, %rax
    jmp     81f
80: CALL_GLOBAL GetLastError                # the file closes
    mov     %eax, %eax
81: mov     %rax, %r15
    mov     %rbp, %rcx
    CALL_GLOBAL CloseHandle
    mov     %r15, %rax
    jmp     92f
85: CALL_GLOBAL GetLastError                # the wide path's memory goes back
    mov     %eax, %r15d
    mov     (L + 32)(%rsp), %rcx
    xor     %edx, %edx
    mov     $OS_MEM_RELEASE, %r8d
    CALL_GLOBAL VirtualFree
    mov     %r15, %rax
    jmp     92f
90: CALL_GLOBAL GetLastError
    mov     %eax, %eax
92: test    %rax, %rax                      # the error, never 0
    jnz     93f
    mov     $1, %eax
93: mov     %rax, (%rbx)
    jmp     99f
91: mov     $OS_ERROR_FILENAME_EXCED_RANGE, %eax
    jmp     93b
99: xor     %eax, %eax
    LEAVE 64
END_FUNCTION lantern_shell_read_file

/*
 * (stream, bytes): docs/reference/shell.md. rbx the handle, rbp the next byte, r12 the bytes
 * left. Locals: L the fifth argument of WriteFile, L+8 the bytes written.
 */
FUNCTION lantern_shell_write
    ENTER 32
    mov     8(%rsi), %rbp
    add     %rsi, %rbp
    mov     16(%rsi), %r12
    mov     $OS_STD_OUTPUT_HANDLE, %ecx
    cmpq    $2, (%rdi)
    jne     1f
    mov     $OS_STD_ERROR_HANDLE, %ecx
1:  CALL_GLOBAL GetStdHandle
    mov     %rax, %rbx
    test    %rax, %rax
    jz      9f
    cmp     $-1, %rax
    je      9f
2:  test    %r12, %r12
    jz      9f
    mov     %rbx, %rcx
    mov     %rbp, %rdx
    mov     %r12, %r8
    mov     $SHELL_IO_MAX, %eax
    cmp     %rax, %r8
    jbe     3f
    mov     %rax, %r8
3:  movq    $0, (L + 8)(%rsp)
    lea     (L + 8)(%rsp), %r9
    movq    $0, L(%rsp)
    CALL_GLOBAL WriteFile
    test    %eax, %eax
    jz      9f
    mov     (L + 8)(%rsp), %eax
    test    %rax, %rax
    jz      9f
    add     %rax, %rbp
    sub     %rax, %r12
    jmp     2b
9:  xor     %eax, %eax
    LEAVE 32
END_FUNCTION lantern_shell_write

/* (out): docs/reference/shell.md. rbx out. Locals: L a FILETIME. */
FUNCTION lantern_shell_time_ms
    ENTER 16
    mov     %rdi, %rbx
    lea     L(%rsp), %rcx
    CALL_GLOBAL GetSystemTimePreciseAsFileTime
    mov     L(%rsp), %rax
    movabs  $OS_UNIX_EPOCH, %rcx
    sub     %rcx, %rax
    xor     %edx, %edx
    mov     $10000, %ecx
    div     %rcx
    mov     %rax, (%rbx)
    xor     %eax, %eax
    LEAVE 16
END_FUNCTION lantern_shell_time_ms
