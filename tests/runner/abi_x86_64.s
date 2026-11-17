/*
 * ABI check for the test runner, x86-64 (System V AMD64 psABI). AT&T syntax. Test code: it is not part of the library.
 *
 * abi_call(ctx) calls ctx.fn with the 11 arguments in ctx, after it sets every
 * register the callee must keep to a known value and paints ctx.paint bytes
 * of stack below the call. It then records in ctx the status, a mask of the
 * kept state that changed, and the bytes of stack the call used.
 * The layout of ctx and the bits of the mask are in tests/runner/README.md.
 *
 * It makes no unwind entries for its own frame: it runs only inside the runner.
 */

.set ISA_X86_64, 1
.include "platform.inc"

.set PAINT, 0x5a5a5a5a5a5a5a5a

FUNCTION abi_call
    UNWIND_END_PROLOGUE
    push    %rbx
    push    %rbp
    push    %r12
    push    %r13
    push    %r14
    push    %r15
    push    %rdi
    /* Paint the stack below, from the top down, so each page is touched in order. */
    mov     48(%rdi), %rcx
    mov     %rsp, %rax
    movabs  $PAINT, %rdx
1:  sub     $8, %rax
    mov     %rdx, (%rax)
    sub     $8, %rcx
    jnz     1b
    mov     %rsp, 80(%rdi)
    stmxcsr 88(%rdi)
    fnstcw  92(%rdi)
    /* r15 keeps ctx; the other kept registers get known values. */
    mov     %rdi, %r15
    movabs  $0x0f1e2d3c4b5a6978, %rbx
    movabs  $0x101f2e3d4c5b6a79, %rbp
    movabs  $0x11202f3e4d5c6b7a, %r12
    movabs  $0x1221303f4e5d6c7b, %r13
    movabs  $0x132231404f5e6d7c, %r14
    mov     (%r15), %r11
    mov     16(%r15), %rsi
    mov     24(%r15), %rdx
    mov     32(%r15), %rcx
    mov     40(%r15), %r8
    mov     112(%r15), %r9
    sub     $48, %rsp                       /* arguments 7 to 11 on the stack */
    mov     120(%r15), %rax
    mov     %rax, 0(%rsp)
    mov     128(%r15), %rax
    mov     %rax, 8(%rsp)
    mov     136(%r15), %rax
    mov     %rax, 16(%rsp)
    mov     144(%r15), %rax
    mov     %rax, 24(%rsp)
    mov     152(%r15), %rax
    mov     %rax, 32(%rsp)
    mov     8(%r15), %rdi
    call    *%r11
    add     $48, %rsp
    xor     %ecx, %ecx
    movabs  $0x0f1e2d3c4b5a6978, %rdx
    cmp     %rdx, %rbx
    je      10f
    bts     $0, %rcx
10:
    movabs  $0x101f2e3d4c5b6a79, %rdx
    cmp     %rdx, %rbp
    je      11f
    bts     $1, %rcx
11:
    movabs  $0x11202f3e4d5c6b7a, %rdx
    cmp     %rdx, %r12
    je      12f
    bts     $2, %rcx
12:
    movabs  $0x1221303f4e5d6c7b, %rdx
    cmp     %rdx, %r13
    je      13f
    bts     $3, %rcx
13:
    movabs  $0x132231404f5e6d7c, %rdx
    cmp     %rdx, %r14
    je      14f
    bts     $4, %rcx
14:
    /* Check the stack pointer, put it back, then check r15 against the copy of ctx on the stack. */
    mov     %r15, %rdi
    cmp     80(%rdi), %rsp
    je      15f
    bts     $63, %rcx
15:
    mov     80(%rdi), %rsp
    cmp     (%rsp), %r15
    je      16f
    bts     $5, %rcx
16:
    mov     %rax, 56(%rdi)
    /* The lowest painted word that changed gives the stack the call used. */
    mov     %rsp, %r9
    sub     48(%rdi), %r9
    movabs  $PAINT, %rdx
2:  cmp     %rsp, %r9
    jae     3f
    cmp     %rdx, (%r9)
    jne     3f
    add     $8, %r9
    jmp     2b
3:  mov     %rsp, %r10
    sub     %r9, %r10
    mov     %r10, 72(%rdi)
    stmxcsr 96(%rdi)
    fnstcw  100(%rdi)
    mov     96(%rdi), %edx              /* MXCSR control bits only: status flags 0-5 are not kept (psABI) */
    xor     88(%rdi), %edx
    and     $0xFFC0, %edx
    jz      17f
    bts     $61, %rcx
17:
    movzwl  100(%rdi), %edx
    movzwl  92(%rdi), %r8d
    cmp     %r8d, %edx
    je      18f
    bts     $60, %rcx
18:
    pushf
    pop     %rdx
    bt      $10, %rdx
    jnc     19f
    bts     $62, %rcx
19:
    /* Put the flags and control words back for the C caller. */
    cld
    ldmxcsr 88(%rdi)
    fldcw   92(%rdi)
    mov     %rcx, 64(%rdi)
    add     $8, %rsp
    pop     %r15
    pop     %r14
    pop     %r13
    pop     %r12
    pop     %rbp
    pop     %rbx
    ret
END_FUNCTION abi_call
