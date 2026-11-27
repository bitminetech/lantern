/*
 * The entry point of the lantern binary for Linux on x86-64: the arguments, without the program
 * name, as an ArgList; then lantern_app_main; then exit_group with its status.
 * Requirements: docs/reference/shell.md, _start. At _start, rsp holds argc, then argv.
 * r12 the argument count, r13 argv, r14 the argument bytes, r15 the ArgList's size, rbx the ArgList.
 */
.set ISA_X86_64, 1
.include "ssz.inc"
.include "crypto.inc"
.include "bls12381.inc"
.include "kzg.inc"
.include "preset.inc"
.include "lantern.inc"
.include "platform.inc"

.set SYS_EXIT_GROUP, 231

    .text
    .globl _start
    .p2align 4
_start:
    xor     %ebp, %ebp
    mov     (%rsp), %r12
    lea     16(%rsp), %r13                  # argv[1]
    dec     %r12
    xor     %r14d, %r14d                    # the bytes of every argument
    xor     %ecx, %ecx
1:  cmp     %r12, %rcx
    jae     3f
    mov     (%r13,%rcx,8), %rsi
    xor     %edx, %edx
2:  cmpb    $0, (%rsi,%rdx)
    je      21f
    inc     %rdx
    jmp     2b
21: add     %rdx, %r14
    inc     %rcx
    jmp     1b
3:  mov     %r12, %rax                      # the ArgList: 40 bytes, the Arg entries, the bytes
    shl     $4, %rax
    lea     (40 + 7)(%rax,%r14), %r15
    and     $-8, %r15
    sub     $16, %rsp
    mov     %r15, (%rsp)
    mov     %rsp, %rdi
    lea     8(%rsp), %rsi
    call    lantern_shell_map
    mov     8(%rsp), %rbx
    test    %rbx, %rbx
    jz      9f
    mov     %r15, (%rbx)
    movq    $40, 8(%rbx)
    mov     %r12, 16(%rbx)
    mov     %r12, %r8
    shl     $4, %r8
    add     $40, %r8
    mov     %r8, 24(%rbx)
    mov     %r14, 32(%rbx)
    xor     %r9d, %r9d
4:  cmp     %r12, %r9
    jae     6f
    mov     (%r13,%r9,8), %rsi
    mov     %r9, %rax
    shl     $4, %rax
    mov     %r8, 40(%rbx,%rax)
    xor     %edx, %edx
5:  movzbl  (%rsi,%rdx), %ecx
    test    %ecx, %ecx
    jz      51f
    mov     %cl, (%rbx,%r8)
    inc     %r8
    inc     %rdx
    jmp     5b
51: mov     %rdx, 48(%rbx,%rax)
    inc     %r9
    jmp     4b
6:  mov     %rbx, %rdi
    xor     %eax, %eax                      # the sha variant (shell.md, The sha variant): cpuid
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
    bt      $8, %ebx                        # BMI2, for asm-crypto's bls12381x.s
    jnc     60f
    bt      $19, %ebx                       # ADX
    jnc     60f
    call    lx_lantern_app_main
    mov     %eax, %edi
    jmp     8f
60: call    lantern_app_main
    mov     %eax, %edi
    jmp     8f
9:  mov     $2, %edi                        # no memory for the arguments
8:  mov     $SYS_EXIT_GROUP, %eax
    syscall
