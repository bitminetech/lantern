/*
 * The entry point of the lantern binary for Windows on x86-64: mainCRTStartup; the command line
 * of GetCommandLineW split by CommandLineToArgvW, without the program name, each argument in
 * UTF-8, as an ArgList; then lantern_app_main; then ExitProcess with its status.
 * Requirements: docs/reference/shell.md, mainCRTStartup. r12 the argument count, r13 the wide
 * arguments, r14 the UTF-8 bytes or the next byte, r15 the ArgList's size, rbx the ArgList, rbp
 * an argument's number. Locals: L the stack arguments of a call, L+64 argc, L+72 the size, L+80
 * the address.
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

.set OS_CP_UTF8, 65001                      /* winnls.h */

FUNCTION mainCRTStartup
    ENTER 96
    CALL_GLOBAL GetCommandLineW
    mov     %rax, %rcx
    lea     (L + 64)(%rsp), %rdx
    CALL_GLOBAL CommandLineToArgvW
    test    %rax, %rax
    jz      9f
    mov     %rax, %r13
    movslq  (L + 64)(%rsp), %r12            # without the program name
    dec     %r12
    jns     0f
    xor     %r12d, %r12d
0:  xor     %r14d, %r14d                    # the UTF-8 bytes of every argument
    xor     %ebp, %ebp
1:  cmp     %r12, %rbp
    jae     3f
    mov     $OS_CP_UTF8, %ecx
    xor     %edx, %edx
    mov     8(%r13,%rbp,8), %r8
    mov     $-1, %r9d
    movq    $0, L(%rsp)
    movq    $0, (L + 8)(%rsp)
    movq    $0, (L + 16)(%rsp)
    movq    $0, (L + 24)(%rsp)
    CALL_GLOBAL WideCharToMultiByte
    mov     %eax, %eax                      # an int: the upper half is not part of it
    test    %eax, %eax                      # its bytes, and a zero
    jz      2f
    dec     %eax
2:  add     %rax, %r14
    inc     %rbp
    jmp     1b
3:  mov     %r12, %rax                      # the ArgList: 40 bytes, the Arg entries, the bytes, room for a zero
    shl     $4, %rax
    lea     (40 + 8)(%rax,%r14), %r15
    and     $-8, %r15
    mov     %r15, (L + 72)(%rsp)
    lea     (L + 72)(%rsp), %rdi
    lea     (L + 80)(%rsp), %rsi
    CALL_GLOBAL lantern_shell_map
    mov     (L + 80)(%rsp), %rbx
    test    %rbx, %rbx
    jz      9f
    mov     %r15, (%rbx)
    movq    $40, 8(%rbx)
    mov     %r12, 16(%rbx)
    mov     %r12, %rax
    shl     $4, %rax
    add     $40, %rax
    mov     %rax, 24(%rbx)
    mov     %r14, 32(%rbx)
    mov     %rax, %r14                      # the next byte
    xor     %ebp, %ebp
4:  cmp     %r12, %rbp
    jae     6f
    mov     %rbp, %rax
    shl     $4, %rax
    mov     %r14, 40(%rbx,%rax)
    mov     $OS_CP_UTF8, %ecx
    xor     %edx, %edx
    mov     8(%r13,%rbp,8), %r8
    mov     $-1, %r9d
    lea     (%rbx,%r14), %rax
    mov     %rax, L(%rsp)
    mov     %r15, %rax
    sub     %r14, %rax
    mov     %rax, (L + 8)(%rsp)
    movq    $0, (L + 16)(%rsp)
    movq    $0, (L + 24)(%rsp)
    CALL_GLOBAL WideCharToMultiByte
    mov     %eax, %eax                      # an int: the upper half is not part of it
    test    %eax, %eax
    jz      5f
    dec     %eax
5:  mov     %rbp, %rcx
    shl     $4, %rcx
    mov     %rax, 48(%rbx,%rcx)
    add     %rax, %r14
    inc     %rbp
    jmp     4b
6:  mov     %r13, %rcx
    CALL_GLOBAL LocalFree
    mov     %rbx, %rdi
    xor     %eax, %eax                      # the sha variant (README, Target profile): cpuid
    cpuid
    cmp     $7, %eax
    jb      60f
    mov     $1, %eax
    cpuid
    bt      $9, %ecx                        # SSSE3
    jnc     60f
    mov     $7, %eax
    xor     %ecx, %ecx
    cpuid
    bt      $29, %ebx                       # SHA
    jnc     60f
    CALL_GLOBAL lx_lantern_app_main
    mov     %eax, %ecx
    CALL_GLOBAL ExitProcess
60: CALL_GLOBAL lantern_app_main
    mov     %eax, %ecx
    CALL_GLOBAL ExitProcess
9:  mov     $2, %ecx                        # no memory for the arguments
    CALL_GLOBAL ExitProcess
END_FUNCTION mainCRTStartup
