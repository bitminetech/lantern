/*
 * Light client data, x86-64. Requirements: docs/reference/light-client.md.
 */

.if FORK >= FORK_ALTAIR
.set LCH_FIXED, 112                          # a LightClientHeader: beacon
.set LCU_BRANCH, 32 * 5                      # next_sync_committee_branch
.set LCU_FINALITY, 32 * 6                    # finality_branch
.if FORK >= FORK_ELECTRA
.set LCU_BRANCH, 32 * 6
.set LCU_FINALITY, 32 * 7
.endif
.if FORK >= FORK_CAPELLA
.set LCH_FIXED, 112 + 4 + 32 * 4             # beacon, the offset of execution, execution_branch
.set LCU_HEADER, 4                           # the headers of an update: offsets
.else
.set LCU_HEADER, LCH_FIXED
.endif
.set LCU_NEXT, LCU_HEADER + 48 * SYNC_COMMITTEE_SIZE + 48   # next_sync_committee_branch
.set LCU_FINALIZED, LCU_NEXT + LCU_BRANCH                   # finalized_header, or its offset
.set LCU_FINALITY_AT, LCU_FINALIZED + LCU_HEADER            # finality_branch
.set LCU_BITS, LCU_FINALITY_AT + LCU_FINALITY               # sync_aggregate.sync_committee_bits
.set LCU_SIGNATURE_SLOT, LCU_BITS + SYNC_COMMITTEE_SIZE / 8 + 96
.set LCU_FIXED, LCU_SIGNATURE_SLOT + 8

# The fields of the LightClientUpdate ByteList rdi that is_better_update compares: rax = 0 with rcx
# the participants, rdx attested_header.beacon.slot, rsi finalized_header.beacon.slot, rdi
# signature_slot, r8 1 with a next_sync_committee_branch not all zero, r9 1 with a finality_branch
# not all zero; rax = 1 for bytes that are no update of the fork. Uses r10, r11.
LOCAL_FUNCTION lc_update_fields
    UNWIND_END_PROLOGUE
    mov     8(%rdi), %r10
    add     %rdi, %r10                      # the bytes, r11 of them
    mov     16(%rdi), %r11
    cmp     $LCU_FIXED, %r11
    jb      9f
.if FORK >= FORK_CAPELLA
    mov     (%r10), %eax                    # the headers: at their offsets, the first at the fixed part
    mov     LCU_FINALIZED(%r10), %ecx
    cmp     $LCU_FIXED, %rax
    jne     9f
    lea     LCH_FIXED(%rax), %rdx
    cmp     %rcx, %rdx
    ja      9f
    lea     LCH_FIXED(%rcx), %rdx
    cmp     %r11, %rdx
    ja      9f
    mov     (%r10,%rax), %rdx
    mov     (%r10,%rcx), %rsi
.else
    mov     (%r10), %rdx
    mov     LCU_FINALIZED(%r10), %rsi
.endif
    mov     LCU_SIGNATURE_SLOT(%r10), %rdi
    xor     %ecx, %ecx                      # the participants
    xor     %r8d, %r8d
1:  cmp     $(SYNC_COMMITTEE_SIZE / 8), %r8
    jae     3f
    movzbl  LCU_BITS(%r10,%r8), %eax
2:  test    %eax, %eax
    jz      21f
    lea     -1(%rax), %r9d
    and     %r9d, %eax
    inc     %rcx
    jmp     2b
21: inc     %r8
    jmp     1b
3:  xor     %eax, %eax                      # the branches: any byte not zero
    xor     %r9d, %r9d
31: cmp     $(LCU_BRANCH / 8), %r9
    jae     32f
    or      LCU_NEXT(%r10,%r9,8), %rax
    inc     %r9
    jmp     31b
32: xor     %r8d, %r8d
    test    %rax, %rax
    setnz   %r8b
    xor     %eax, %eax
    xor     %r9d, %r9d
33: cmp     $(LCU_FINALITY / 8), %r9
    jae     34f
    or      LCU_FINALITY_AT(%r10,%r9,8), %rax
    inc     %r9
    jmp     33b
34: xor     %r9d, %r9d
    test    %rax, %rax
    setnz   %r9b
    xor     %eax, %eax
    ret
9:  mov     $1, %eax
    ret
END_FUNCTION lc_update_fields
.endif

# rax = the sync committee period of the slot src. Uses rcx, rdx.
.macro LC_PERIOD src
    mov     \src, %rax
    xor     %edx, %edx
    mov     $(SLOTS_PER_EPOCH * EPOCHS_PER_SYNC_COMMITTEE_PERIOD), %ecx
    div     %rcx
.endm

# (new, old, out) -> rax: is_better_update of two updates (light-client.md). r12 out, r13 old; the
# fields of new: rbx participants, rbp attested slot, r14 finalized slot, r15 signature slot, S7 a
# sync committee branch, S8 a finality branch. Locals: the fields of old, in that order.
SPEC_FUNCTION is_better_update
    ENTER 48
.if FORK == FORK_PHASE0
    mov     $LANTERN_NO_STATE_ANSWER, %eax
    LEAVE 48
.else
    mov     %rdx, %r12
    mov     %rsi, %r13
    call    lc_update_fields
    test    %rax, %rax
    jnz     96f
    mov     %rcx, %rbx
    mov     %rdx, %rbp
    mov     %rsi, %r14
    mov     %rdi, %r15
    mov     %r8, S7(%rsp)
    mov     %r9, S8(%rsp)
    mov     %r13, %rdi
    call    lc_update_fields
    test    %rax, %rax
    jnz     96f
    mov     %rcx, L(%rsp)
    mov     %rdx, (L + 8)(%rsp)
    mov     %rsi, (L + 16)(%rsp)
    mov     %rdi, (L + 24)(%rsp)
    mov     %r8, (L + 32)(%rsp)
    mov     %r9, (L + 40)(%rsp)
    xor     %r8d, %r8d                      # supermajority: participants * 3 >= SYNC_COMMITTEE_SIZE * 2
    imul    $3, %rbx, %rax
    cmp     $(SYNC_COMMITTEE_SIZE * 2), %rax
    setae   %r8b
    xor     %r9d, %r9d
    imul    $3, L(%rsp), %rax
    cmp     $(SYNC_COMMITTEE_SIZE * 2), %rax
    setae   %r9b
    cmp     %r9, %r8
    jne     80f
    test    %r8, %r8
    jnz     1f
    cmp     L(%rsp), %rbx                   # neither: the more participants
    jne     81f
1:  LC_PERIOD %rbp                          # a relevant sync committee: a branch, and the attested and signature periods equal
    mov     %rax, %r10
    LC_PERIOD %r15
    xor     %r8d, %r8d
    cmp     %rax, %r10
    sete    %r8b
    and     S7(%rsp), %r8
    LC_PERIOD (L + 8)(%rsp)
    mov     %rax, %r10
    LC_PERIOD (L + 24)(%rsp)
    xor     %r9d, %r9d
    cmp     %rax, %r10
    sete    %r9b
    and     (L + 32)(%rsp), %r9
    cmp     %r9, %r8
    jne     80f
    mov     S8(%rsp), %r8                   # finality
    mov     (L + 40)(%rsp), %r9
    cmp     %r9, %r8
    jne     80f
    test    %r8, %r8
    jz      2f
    LC_PERIOD %r14                          # sync committee finality: the finalized and attested periods equal
    mov     %rax, %r10
    LC_PERIOD %rbp
    xor     %r8d, %r8d
    cmp     %rax, %r10
    sete    %r8b
    LC_PERIOD (L + 16)(%rsp)
    mov     %rax, %r10
    LC_PERIOD (L + 8)(%rsp)
    xor     %r9d, %r9d
    cmp     %rax, %r10
    sete    %r9b
    cmp     %r9, %r8
    jne     80f
2:  cmp     L(%rsp), %rbx                   # the more participants
    jne     81f
    cmp     (L + 8)(%rsp), %rbp             # the lower attested slot
    jne     82f
    cmp     (L + 24)(%rsp), %r15            # the lower signature slot
82: setb    %al
    jmp     85f
81: seta    %al
    jmp     85f
80: mov     %r8d, %eax                      # the side that has it
85: movzbl  %al, %eax
    mov     %rax, (%r12)
    xor     %eax, %eax
    LEAVE 48
96: mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 48
.endif
SPEC_END is_better_update

# (body, scratch, out) -> rax: the branch of execution_payload of a body (light-client.md). rbx body,
# rbp scratch, r12 out, r13 the body's value, r14 a Branch at the end of scratch, S9 the scratch's
# size on entry. Locals: L the generalized index.
SPEC_FUNCTION execution_branch
    ENTER 16
.if FORK < FORK_CAPELLA
    mov     $LANTERN_NO_STATE_ANSWER, %eax
    LEAVE 16
.else
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rbp), %rax
    mov     %rax, S9(%rsp)
    ADDRESS %rdi, lantern_type_BeaconBlockBody
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    call    node_decode
    cmp     $1, %rax
    je      99f
    test    %rax, %rax
    jnz     96f
    mov     %rdx, %r13
    mov     (%rbp), %rax
    sub     $(24 + 8 * 32), %rax
    jb      99f
    mov     %rax, (%rbp)
    lea     (%rbp,%rax), %r14
    movq    $(24 + 8 * 32), (%r14)
    movq    $24, 8(%r14)
    movq    $0, 16(%r14)
    movq    $EXECUTION_PAYLOAD_GINDEX, L(%rsp)
    ADDRESS %rdi, lantern_type_BeaconBlockBody
    mov     %r13, %rsi
    lea     L(%rsp), %rdx
    mov     %rbp, %rcx
    mov     %r14, %r8
    CALL_GLOBAL ssz_build_proof
    cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    je      99f
    test    %rax, %rax
    jnz     96f
    mov     16(%r14), %rdx
    shl     $5, %rdx
    lea     24(%r14), %rsi
    mov     %r12, %rdi
    call    lantern_copy
    mov     S9(%rsp), %rax
    mov     %rax, (%rbp)
    xor     %eax, %eax
    LEAVE 16
96: mov     S9(%rsp), %rcx
    mov     %rcx, (%rbp)
    mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 16
99: mov     S9(%rsp), %rcx
    mov     %rcx, (%rbp)
    mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
.endif
SPEC_END execution_branch
