/*
 * Macros of the x86-64 core. Included once by lantern.s. AT&T syntax.
 * Register use follows the ARM64 core: rbx, rbp, r12-r15 for its x19-x24, and the
 * stack slots S7-S10 for x25-x28; rax, rcx, rdx, rsi, rdi, r8 and r9 for temporaries;
 * r10 and r11 for these macros; xmm0-xmm2 for 32-byte copies and compares.
 */

/*
 * Frame of a non-leaf function: rbx, rbp, r12-r15 pushed, then the slots S7-S10 at
 * rsp + 0 and the locals at rsp + L. locals: a multiple of 16.
 */
.macro ENTER locals
    push    %rbx
    UNWIND_PUSH %rbx
    push    %rbp
    UNWIND_PUSH %rbp
    push    %r12
    UNWIND_PUSH %r12
    push    %r13
    UNWIND_PUSH %r13
    push    %r14
    UNWIND_PUSH %r14
    push    %r15
    UNWIND_PUSH %r15
    sub     $(\locals + 40), %rsp
    UNWIND_ALLOC (\locals + 40)
    UNWIND_END_PROLOGUE
.endm

.macro LEAVE locals
    UNWIND_BEGIN_EPILOGUE
    add     $(\locals + 40), %rsp
    UNWIND_FREE (\locals + 40)
    pop     %r15
    UNWIND_POP %r15
    pop     %r14
    UNWIND_POP %r14
    pop     %r13
    UNWIND_POP %r13
    pop     %r12
    UNWIND_POP %r12
    pop     %rbp
    UNWIND_POP %rbp
    pop     %rbx
    UNWIND_POP %rbx
    UNWIND_END_EPILOGUE
    ret
.endm

/* The four saved slots, then the locals of a non-leaf function. */
.set S7, 0
.set S8, 8
.set S9, 16
.set S10, 24
.set L, 32

/* Frame of a small non-leaf function: locals at rsp + 0. locals: a multiple of 16. */
.macro FRAME locals
    sub     $(\locals + 8), %rsp
    UNWIND_ALLOC (\locals + 8)
    UNWIND_END_PROLOGUE
.endm

.macro UNFRAME locals
    UNWIND_BEGIN_EPILOGUE
    add     $(\locals + 8), %rsp
    UNWIND_FREE (\locals + 8)
    UNWIND_END_EPILOGUE
    ret
.endm

/* A leaf function needs no frame. */
.macro LEAF name
    FUNCTION \name
    UNWIND_END_PROLOGUE
.endm

.macro RETURN_OK
    xor     %eax, %eax
    ret
.endm

/* reg = imm, for any 64-bit imm. */
.macro MOVQ reg, imm
.if ((\imm) >= -0x80000000) && ((\imm) <= 0x7fffffff)
    mov     $(\imm), \reg
.else
    movabs  $(\imm), \reg
.endif
.endm

/* A part of a value: base = value + its PartRef's offset, count = the PartRef's count. base is not value. */
.macro PART base, count, value, ref
    mov     ((\ref) + 8)(\value), \count
    mov     (\ref)(\value), \base
    add     \value, \base
.endm

/* dst = &state.validators[idx] of state st. dst is not st or idx. Uses r11. */
.macro VALIDATOR dst, st, idx
    mov     BeaconState_validators(\st), \dst
    add     \st, \dst
    mov     \idx, %r11
    shl     $7, %r11
    add     %r11, \dst
.endm

/* dst = 32 bytes at src. Uses xmm0, xmm1. */
.macro COPY32 dst, src
    movdqu  (\src), %xmm0
    movdqu  16(\src), %xmm1
    movdqu  %xmm0, (\dst)
    movdqu  %xmm1, 16(\dst)
.endm

/* Branch to label when the 32 bytes at a and at b differ. Uses xmm0-xmm2, r11. */
.macro NE32 a, b, label
    movdqu  (\a), %xmm0
    movdqu  (\b), %xmm1
    pcmpeqb %xmm1, %xmm0
    movdqu  16(\a), %xmm1
    movdqu  16(\b), %xmm2
    pcmpeqb %xmm2, %xmm1
    pand    %xmm1, %xmm0
    pmovmskb %xmm0, %r11d
    cmp     $0xffff, %r11d
    jne     \label
.endm

/* Branch to fail when scratch s has fewer than S(k) + extra bytes for the validators of state st. Uses r10, r11. */
.macro NEED_SCRATCH_B s, st, k, extra, fail
    mov     (BeaconState_validators + 8)(\st), %r10
    lea     LIST_FIXED(,%r10,8), %r10
    imul    $(\k), %r10, %r10
    MOVQ    %r11, (LANTERN_SCRATCH_FIXED + (\extra))
    add     %r11, %r10
    cmp     %r10, (\s)
    jb      \fail
.endm

.macro NEED_SCRATCH s, st, k, fail
    NEED_SCRATCH_B \s, \st, \k, 0, \fail
.endm

/* dst = list i of scratch s, whose size is tot: s + tot - (i + 1) * L(n), with its size set. Uses r10, r11. */
.macro SCRATCH_LIST dst, s, tot, i, nreg
    lea     LIST_FIXED(,\nreg,8), %r10
    imul    $((\i) + 1), %r10, %r11
    mov     \tot, \dst
    sub     %r11, \dst
    add     \s, \dst
    mov     %r10, (\dst)
.endm

/* dst = list number ireg (a register) of scratch s, whose size is tot, with its size set. Uses r10, r11. */
.macro SCRATCH_LIST_R dst, s, tot, ireg, nreg
    lea     LIST_FIXED(,\nreg,8), %r10
    lea     1(\ireg), %r11
    imul    %r10, %r11
    mov     \tot, \dst
    sub     %r11, \dst
    add     \s, \dst
    mov     %r10, (\dst)
.endm

/* Give a callee scratch s without its last k lists: its size becomes tot - k * L(n). Uses r10, r11. */
.macro SCRATCH_GIVE s, tot, k, nreg
    lea     LIST_FIXED(,\nreg,8), %r10
    imul    $(\k), %r10, %r10
    mov     \tot, %r11
    sub     %r10, %r11
    mov     %r11, (\s)
.endm

/*
 * Walk the ascending list at cursor cur (end end) to the first entry >= v;
 * set flag to 1 when it equals v, else 0. Uses r11.
 */
.macro IN_SORTED v, cur, end, flag
    mov     $0, \flag
95: cmp     \end, \cur
    jae     98f
    mov     (\cur), %r11
    cmp     \v, %r11
    jae     97f
    add     $8, \cur
    jmp     95b
97: jne     98f
    mov     $1, \flag
98:
.endm

/*
 * After a call to a function that changes no state, with its status in rax:
 * go on when 0; return rax through fail when it is LANTERN_BUFFER_TOO_SMALL;
 * else write it to the result at register res and branch to done.
 */
.macro CHECK_STATUS res, fail, done
    test    %rax, %rax
    jz      99f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      \fail
    mov     %rax, (\res)
    jmp     \done
99:
.endm

/* reg = the address of label, in this object. */
.macro ADDRESS reg, label
    lea     \label(%rip), \reg
.endm

/* Call lantern_<fork>_<name> for the fork in r10 (FORK_PHASE0 to FORK_FULU). */
.macro FORK_CALL name
    cmp     $FORK_ALTAIR, %r10
    jae     81f
    CALL_GLOBAL lantern_phase0_\name
    jmp     89f
81: cmp     $FORK_BELLATRIX, %r10
    jae     82f
    CALL_GLOBAL lantern_altair_\name
    jmp     89f
82: cmp     $FORK_CAPELLA, %r10
    jae     83f
    CALL_GLOBAL lantern_bellatrix_\name
    jmp     89f
83: cmp     $FORK_DENEB, %r10
    jae     84f
    CALL_GLOBAL lantern_capella_\name
    jmp     89f
84: cmp     $FORK_ELECTRA, %r10
    jae     85f
    CALL_GLOBAL lantern_deneb_\name
    jmp     89f
85: cmp     $FORK_FULU, %r10
    jae     86f
    CALL_GLOBAL lantern_electra_\name
    jmp     89f
86: CALL_GLOBAL lantern_fulu_\name
89:
.endm

/* Call lantern_<fork>_<name> for the fork in r10, bellatrix to fulu. */
.macro FORK_CALL_BELLATRIX name
    cmp     $FORK_CAPELLA, %r10
    jae     91f
    CALL_GLOBAL lantern_bellatrix_\name
    jmp     96f
91: cmp     $FORK_DENEB, %r10
    jae     92f
    CALL_GLOBAL lantern_capella_\name
    jmp     96f
92: cmp     $FORK_ELECTRA, %r10
    jae     93f
    CALL_GLOBAL lantern_deneb_\name
    jmp     96f
93: cmp     $FORK_FULU, %r10
    jae     94f
    CALL_GLOBAL lantern_electra_\name
    jmp     96f
94: CALL_GLOBAL lantern_fulu_\name
96:
.endm
