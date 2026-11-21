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

.set LC_EPH_EXTRA, 436                       # an ExecutionPayloadHeader's SSZ bytes: the offset of extra_data
.set LC_EPH_CAPELLA, 568                     # the fixed part of capella's
.set LC_EPH_DENEB, 584                       # of deneb's, electra's and fulu's: blob_gas_used, excess_blob_gas
.set LC_EPH_FIXED, LC_EPH_CAPELLA
.if FORK >= FORK_DENEB
.set LC_EPH_FIXED, LC_EPH_DENEB
.endif
.set LC_HEADER_EXECUTION, 112 + 4 + 32 * 4   # a LightClientHeader from capella: where execution starts
.set LC_BODY_PAYLOAD, 220 + SYNC_COMMITTEE_SIZE / 8 + 96   # a BlindedBeaconBlockBody's SSZ bytes: the offset of execution_payload_header

# (block, scratch, out) -> rax: block_to_light_client_header of the block (light-client.md). rbx
# block, rbp scratch, r12 out, r13 the message, r14 the body, r15 the bytes of out; S7 a Branch or
# the blinded block at the end of scratch, S8 the header's bytes, S9 the scratch's size on entry,
# S10 the size after the decoded block. Locals: L the generalized index.
SPEC_FUNCTION block_to_light_client_header
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rbp), %rax
    mov     %rax, S9(%rsp)
    mov     (%r12), %rax                    # out: room for the beacon header; from capella, the branch and a payload header too
    sub     $24, %rax
    jb      98f
.if FORK >= FORK_CAPELLA
    cmp     $(LC_HEADER_EXECUTION + LC_EPH_FIXED), %rax
.else
    cmp     $112, %rax
.endif
    jb      98f
    ADDRESS %rdi, lantern_type_SignedBeaconBlock
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    call    node_decode
    cmp     $1, %rax
    je      98f
    test    %rax, %rax
    jnz     96f
    PART    %r13, %rcx, %rdx, SignedBeaconBlock_message
    PART    %r14, %rcx, %r13, BeaconBlock_body
    mov     (%rbp), %rax
    mov     %rax, S10(%rsp)
    lea     24(%r12), %r15
    movq    $24, 8(%r12)
    mov     BeaconBlock_slot(%r13), %rax    # beacon
    mov     %rax, (%r15)
    mov     BeaconBlock_proposer_index(%r13), %rax
    mov     %rax, 8(%r15)
    lea     16(%r15), %rdi
    lea     BeaconBlock_parent_root(%r13), %rsi
    COPY32  %rdi, %rsi
    lea     48(%r15), %rdi
    lea     BeaconBlock_state_root(%r13), %rsi
    COPY32  %rdi, %rsi
    ADDRESS %rdi, lantern_type_BeaconBlockBody
    mov     %r14, %rsi
    mov     %rbp, %rdx
    lea     80(%r15), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    je      98f
    test    %rax, %rax
    jnz     96f
    movq    $112, S8(%rsp)
.if FORK >= FORK_CAPELLA
    mov     S10(%rsp), %rax                 # execution_branch: ssz_build_proof of the body at 25
    sub     $(24 + 8 * 32), %rax
    jb      98f
    mov     %rax, (%rbp)
    lea     (%rbp,%rax), %rcx
    mov     %rcx, S7(%rsp)
    movq    $(24 + 8 * 32), (%rcx)
    movq    $24, 8(%rcx)
    movq    $0, 16(%rcx)
    movq    $EXECUTION_PAYLOAD_GINDEX, L(%rsp)
    ADDRESS %rdi, lantern_type_BeaconBlockBody
    mov     %r14, %rsi
    lea     L(%rsp), %rdx
    mov     %rbp, %rcx
    mov     S7(%rsp), %r8
    CALL_GLOBAL ssz_build_proof
    mov     S10(%rsp), %rcx
    mov     %rcx, (%rbp)
    cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    je      98f
    test    %rax, %rax
    jnz     96f
    lea     116(%r15), %rdi
    mov     S7(%rsp), %rsi
    add     $24, %rsi
    mov     $128, %edx
    call    lantern_copy
    movl    $LC_HEADER_EXECUTION, 112(%r15)
    mov     16(%rbx), %rax                  # execution: of the blinded block, at the end of scratch
    add     $(24 + 1024 + 7), %rax
    and     $~7, %rax
    mov     S10(%rsp), %rcx
    sub     %rax, %rcx
    jb      98f
    mov     %rcx, (%rbp)
    lea     (%rbp,%rcx), %rdx
    mov     %rdx, S7(%rsp)
    mov     %rax, (%rdx)
    movq    $24, 8(%rdx)
    movq    $0, 16(%rdx)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    lantern_node_blinded_block
    mov     S10(%rsp), %rcx
    mov     %rcx, (%rbp)
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      98f
    test    %rax, %rax
    jnz     96f
    mov     S7(%rsp), %rsi                  # its bytes: the message, the body, the header's offsets
    mov     8(%rsi), %rax
    add     %rax, %rsi
    mov     (%rsi), %eax
    add     %rax, %rsi
    mov     80(%rsi), %eax
    add     %rax, %rsi
    mov     LC_BODY_PAYLOAD(%rsi), %eax
    mov     (LC_BODY_PAYLOAD + 4)(%rsi), %edx
    sub     %rax, %rdx
    add     %rax, %rsi
    mov     (%r12), %rax                    # out: room for it too; at least LC_EPH_FIXED, as checked first
    sub     $(24 + LC_HEADER_EXECUTION), %rax
    cmp     %rax, %rdx
    ja      98f
    lea     LC_HEADER_EXECUTION(%rdx), %rax
    mov     %rax, S8(%rsp)
    lea     LC_HEADER_EXECUTION(%r15), %rdi
    call    lantern_copy
.endif
    mov     S8(%rsp), %rax
    mov     %rax, 16(%r12)
    mov     S9(%rsp), %rax
    mov     %rax, (%rbp)
    xor     %eax, %eax
    LEAVE 16
96: mov     S9(%rsp), %rcx
    mov     %rcx, (%rbp)
    mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 16
98: mov     S9(%rsp), %rcx
    mov     %rcx, (%rbp)
    mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END block_to_light_client_header

# (header, from, out) -> rax: the header of the fork from as one of the fork (light-client.md). rbx
# the header's bytes, rbp their count, r12 from, r13 out, r14 the bytes of out, r15 the room of out.
SPEC_FUNCTION upgrade_lc_header
    ENTER 0
    cmp     $FORK, %rsi
    ja      97f
    mov     8(%rdi), %rax
    lea     (%rdi,%rax), %rbx
    mov     16(%rdi), %rbp
    mov     %rsi, %r12
    mov     %rdx, %r13
    lea     24(%r13), %r14
    mov     (%r13), %r15
    sub     $24, %r15                       # the room of out
.if FORK >= FORK_CAPELLA
    cmp     $FORK_CAPELLA, %r12
    jae     2f
.endif
    cmp     $112, %rbp                      # before capella: beacon
    jne     96f
.if FORK >= FORK_CAPELLA
    cmp     $(LC_HEADER_EXECUTION + LC_EPH_FIXED), %r15 # to capella or later: an empty payload header and a zero branch
    jb      98f
    mov     %r14, %rdi
    mov     $(LC_HEADER_EXECUTION + LC_EPH_FIXED), %esi
    call    lantern_zero
    mov     %r14, %rdi
    mov     %rbx, %rsi
    mov     $112, %edx
    call    lantern_copy
    movl    $LC_HEADER_EXECUTION, 112(%r14)
    movl    $LC_EPH_FIXED, (LC_HEADER_EXECUTION + LC_EPH_EXTRA)(%r14)
    mov     $(LC_HEADER_EXECUTION + LC_EPH_FIXED), %ebp
    jmp     8f
2:  cmpl    $LC_HEADER_EXECUTION, 112(%rbx) # capella or later: its payload header at 244, extra_data after the fixed part
    jne     96f
    mov     $LC_EPH_DENEB, %eax
    mov     $LC_EPH_CAPELLA, %ecx
    cmp     $FORK_CAPELLA, %r12
    cmove   %rcx, %rax
    lea     LC_HEADER_EXECUTION(%rax), %rcx
    cmp     %rcx, %rbp
    jb      96f
    mov     (LC_HEADER_EXECUTION + LC_EPH_EXTRA)(%rbx), %ecx
    cmp     %rax, %rcx
    jne     96f
.if FORK >= FORK_DENEB
    cmp     $FORK_CAPELLA, %r12             # capella to deneb or later: blob_gas_used and excess_blob_gas 0
    jne     7f
    lea     16(%rbp), %rax
    cmp     %rax, %r15
    jb      98f
    mov     %r14, %rdi
    mov     %rbx, %rsi
    mov     $(LC_HEADER_EXECUTION + LC_EPH_CAPELLA), %edx
    call    lantern_copy
    movq    $0, (LC_HEADER_EXECUTION + LC_EPH_CAPELLA)(%r14)
    movq    $0, (LC_HEADER_EXECUTION + LC_EPH_CAPELLA + 8)(%r14)
    lea     (LC_HEADER_EXECUTION + LC_EPH_CAPELLA + 16)(%r14), %rdi
    lea     (LC_HEADER_EXECUTION + LC_EPH_CAPELLA)(%rbx), %rsi
    lea     -(LC_HEADER_EXECUTION + LC_EPH_CAPELLA)(%rbp), %rdx
    call    lantern_copy
    movl    $LC_EPH_DENEB, (LC_HEADER_EXECUTION + LC_EPH_EXTRA)(%r14)
    add     $16, %rbp
    jmp     8f
.endif
.endif
7:  cmp     %rbp, %r15                      # the same layout: the same bytes
    jb      98f
    mov     %r14, %rdi
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    call    lantern_copy
8:  movq    $24, 8(%r13)
    mov     %rbp, 16(%r13)
    xor     %eax, %eax
    LEAVE 0
96: mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 0
97: mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 0
98: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
SPEC_END upgrade_lc_header

# The offsets that the LcStore functions of the common object read in a state of any fork.
.if BeaconState_finalized_checkpoint != NODE_STATE_FINALIZED
.error "NODE_STATE_FINALIZED is not BeaconState.finalized_checkpoint"
.endif
.if FORK >= FORK_ALTAIR
.if (BeaconState_current_sync_committee != NODE_STATE_CURRENT_SYNC_COMMITTEE) || (BeaconState_next_sync_committee != NODE_STATE_NEXT_SYNC_COMMITTEE) || (SyncCommittee__mem != LC_COMMITTEE)
.error "NODE_STATE_*_SYNC_COMMITTEE or LC_COMMITTEE is not the state's"
.endif
.endif

# (kind, parts, out) -> status: the SSZ bytes of a light client object of the fork from its parts
# (light-client.md). rbx parts, rbp out, r12 the kind's fields (LCO_*, 3 bits each), r13 the bytes
# of the fixed part, r14 of the variable part, r15 the fixed cursor, S7 the variable cursor, S8 the
# bytes of out, S9 and S10 a branch's roots and bytes. Locals: none.
SPEC_FUNCTION lc_object
    ENTER 0
.if FORK == FORK_PHASE0
    mov     $LANTERN_NO_STATE_ANSWER, %eax
    LEAVE 0
.else
    mov     %rsi, %rbx
    mov     %rdx, %rbp
    mov     $LCO_BOOTSTRAP_FIELDS, %r12d
    test    %rdi, %rdi
    jz      1f
    mov     $LCO_UPDATE_FIELDS, %r12d
    cmp     $LC_OBJECT_UPDATE, %rdi
    je      1f
    mov     $LCO_FINALITY_FIELDS, %r12d
    cmp     $LC_OBJECT_FINALITY_UPDATE, %rdi
    je      1f
    mov     $LCO_OPTIMISTIC_FIELDS, %r12d
    cmp     $LC_OBJECT_OPTIMISTIC_UPDATE, %rdi
    jne     97f
1:  xor     %r13d, %r13d                    # the sizes, and the checks, before any write
    xor     %r14d, %r14d
    mov     %r12, %rax
2:  mov     %rax, %rcx
    and     $7, %ecx
    jz      5f
    shr     $3, %rax
    cmp     $LCO_HEADER, %ecx
    je      3f
    cmp     $LCO_FINALIZED, %ecx
    je      31f
    cmp     $LCO_COMMITTEE, %ecx
    jne     21f
    add     $LC_COMMITTEE, %r13
    jmp     2b
21: cmp     $LCO_BRANCH, %ecx
    jne     22f
    cmpq    $(LCU_BRANCH / 32), LcParts_branch_count(%rbx)
    ja      97f
    add     $LCU_BRANCH, %r13
    jmp     2b
22: cmp     $LCO_FINALITY, %ecx
    jne     23f
    cmpq    $(LCU_FINALITY / 32), LcParts_finality_count(%rbx)
    ja      97f
    add     $LCU_FINALITY, %r13
    jmp     2b
23: cmp     $LCO_AGGREGATE, %ecx
    jne     24f
    add     $LC_AGGREGATE, %r13
    jmp     2b
24: add     $8, %r13                        # signature_slot
    jmp     2b
3:  mov     LcParts_header(%rbx), %rdx
    jmp     4f
31: mov     LcParts_finalized_header(%rbx), %rdx
4:  mov     16(%rdx), %rsi                  # a header: rsi bytes at rdi
    mov     8(%rdx), %rdi
    add     %rdx, %rdi
.if FORK >= FORK_CAPELLA
    cmp     $(LC_HEADER_EXECUTION + LC_EPH_FIXED), %rsi
    jb      96f
    cmpl    $LC_HEADER_EXECUTION, 112(%rdi)
    jne     96f
    add     $4, %r13
    add     %rsi, %r14
.else
    cmp     $112, %rsi
    jne     96f
    add     $112, %r13
.endif
    jmp     2b
5:  mov     (%rbp), %rax                    # out: room for both parts
    sub     $24, %rax
    lea     (%r13,%r14), %rcx
    cmp     %rax, %rcx
    ja      98f
    lea     24(%rbp), %rax
    mov     %rax, S8(%rsp)
    mov     %rax, %r15
    add     %r13, %rax
    mov     %rax, S7(%rsp)
6:  mov     %r12, %rcx                      # each field in turn
    and     $7, %ecx
    jz      9f
    shr     $3, %r12
    cmp     $LCO_HEADER, %ecx
    je      7f
    cmp     $LCO_FINALIZED, %ecx
    je      71f
    cmp     $LCO_COMMITTEE, %ecx
    jne     61f
    mov     %r15, %rdi
    mov     LcParts_sync_committee(%rbx), %rsi
    mov     $LC_COMMITTEE, %edx
    add     %rdx, %r15
    call    lantern_copy
    jmp     6b
61: cmp     $LCO_BRANCH, %ecx
    jne     62f
    mov     LcParts_branch(%rbx), %rax
    mov     %rax, S10(%rsp)
    mov     LcParts_branch_count(%rbx), %rax
    mov     %rax, S9(%rsp)
    mov     $(LCU_BRANCH / 32), %eax
    jmp     63f
62: cmp     $LCO_FINALITY, %ecx
    jne     64f
    mov     LcParts_finality_branch(%rbx), %rax
    mov     %rax, S10(%rsp)
    mov     LcParts_finality_count(%rbx), %rax
    mov     %rax, S9(%rsp)
    mov     $(LCU_FINALITY / 32), %eax
63: sub     S9(%rsp), %rax                  # normalize_merkle_branch: zero roots first
    shl     $5, %rax
    mov     %r15, %rdi
    mov     %rax, %rsi
    add     %rax, %r15
    call    lantern_zero
    mov     S9(%rsp), %rdx
    shl     $5, %rdx
    mov     %r15, %rdi
    mov     S10(%rsp), %rsi
    add     %rdx, %r15
    call    lantern_copy
    jmp     6b
64: cmp     $LCO_AGGREGATE, %ecx
    jne     65f
    mov     %r15, %rdi
    mov     LcParts_sync_aggregate(%rbx), %rsi
    mov     $LC_AGGREGATE, %edx
    add     %rdx, %r15
    call    lantern_copy
    jmp     6b
65: mov     LcParts_signature_slot(%rbx), %rax
    mov     %rax, (%r15)
    add     $8, %r15
    jmp     6b
7:  mov     LcParts_header(%rbx), %rax
    jmp     8f
71: mov     LcParts_finalized_header(%rbx), %rax
8:  mov     16(%rax), %rdx
    mov     8(%rax), %rsi
    add     %rax, %rsi
.if FORK >= FORK_CAPELLA
    mov     S7(%rsp), %rdi                  # its offset, then its bytes after the fixed part
    mov     %rdi, %rcx
    sub     S8(%rsp), %rcx
    movl    %ecx, (%r15)
    add     $4, %r15
    add     %rdx, S7(%rsp)
.else
    mov     %r15, %rdi
    add     %rdx, %r15
.endif
    call    lantern_copy
    jmp     6b
9:  movq    $24, 8(%rbp)
    lea     (%r13,%r14), %rax
    mov     %rax, 16(%rbp)
    xor     %eax, %eax
    LEAVE 0
96: mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 0
97: mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 0
98: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
.endif
SPEC_END lc_object
