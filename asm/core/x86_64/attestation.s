/*
 * Committees and attestations, x86-64. Requirements: docs/reference/block-processing.md.
 */

.set CIDX_BYTES, LIST_FIXED + 8 * MAX_COMMITTEES_PER_SLOT     /* an IndexList of committee indices */
.set FLAGS_BYTES, LIST_FIXED + 8 * 3                            /* an IndexList of participation flags */
.set ATTEST_EXTRA, 2 * CIDX_BYTES + IndexedAttestation__fixed + 8

/* ---------------------------------------------------------------- Sorting */

/* Sift the entry at root down the heap of entries below end, at rdi. Uses rax, rcx, rdx, r8. */
.macro SIFT root, end
97: lea     1(\root,\root), %rax            # child = 2 * root + 1
    cmp     \end, %rax
    jae     98f
    mov     (%rdi,%rax,8), %rcx
    lea     1(%rax), %rdx
    cmp     \end, %rdx
    jae     96f
    mov     (%rdi,%rdx,8), %r8
    cmp     %rcx, %r8                       # the larger child
    jbe     96f
    mov     %rdx, %rax
    mov     %r8, %rcx
96: mov     (%rdi,\root,8), %r8
    cmp     %rcx, %r8
    jae     98f
    mov     %rcx, (%rdi,\root,8)
    mov     %r8, (%rdi,%rax,8)
    mov     %rax, \root
    jmp     97b
98:
.endm

/* L0: sort the rsi u64 entries at rdi, ascending (heapsort). A leaf; uses rax, rcx, rdx, r8-r11. */
LOCAL_FUNCTION sort_u64
    UNWIND_END_PROLOGUE
    cmp     $2, %rsi
    jb      9f
    mov     %rsi, %r9
    shr     $1, %r9
1:  test    %r9, %r9
    jz      2f
    dec     %r9
    mov     %r9, %r10
    SIFT    %r10, %rsi
    jmp     1b
2:  mov     %rsi, %r11
3:  dec     %r11
    jz      9f
    mov     (%rdi), %rax
    mov     (%rdi,%r11,8), %rcx
    mov     %rcx, (%rdi)
    mov     %rax, (%rdi,%r11,8)
    xor     %r10d, %r10d
    SIFT    %r10, %r11
    jmp     3b
9:  ret
END_FUNCTION sort_u64

/* ---------------------------------------------------------------- Committees */

SPEC_LEAF get_committee_indices
    movq    $LIST_FIXED, LIST_OFFSET(%rsi)
    lea     LIST_FIXED(%rsi), %rdx
    xor     %ecx, %ecx                      # bit
1:  cmp     $MAX_COMMITTEES_PER_SLOT, %rcx
    jae     2f
    bt      %rcx, (%rdi)
    jnc     3f
    mov     %rcx, (%rdx)
    add     $8, %rdx
3:  inc     %rcx
    jmp     1b
2:  lea     LIST_FIXED(%rsi), %rax
    sub     %rax, %rdx
    shr     $3, %rdx
    mov     %rdx, LIST_COUNT(%rsi)
    RETURN_OK
SPEC_END get_committee_indices

/* rbx state, rbp epoch, r12 scratch, r13 out, r14 list. */
SPEC_FUNCTION get_committee_count_per_slot
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH %r12, %rbx, 1, 9f
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    mov     (%r12), %rax
    SCRATCH_LIST %r14, %r12, %rax, 0, %rcx
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r14, %rdx
    call    lantern_get_active_validator_indices
    test    %rax, %rax
    jnz     7f
    mov     LIST_COUNT(%r14), %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    xor     %edx, %edx
    mov     $TARGET_COMMITTEE_SIZE, %ecx
    div     %rcx
    mov     $MAX_COMMITTEES_PER_SLOT, %ecx
    cmp     %rcx, %rax
    cmovae  %rcx, %rax
    mov     $1, %ecx                        # max(1, ...)
    test    %rax, %rax
    cmovz   %rcx, %rax
    mov     %rax, (%r13)
    xor     %eax, %eax
7:  LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END get_committee_count_per_slot

/*
 * rbx indices, rbp seed, r12 i, r13 end, r14 scratch, r15 out entries, S7 scratch size.
 * Locals: L len(indices), L+8 i, L+16 shuffled.
 */
SPEC_FUNCTION compute_committee
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %r8, %r14
    mov     LIST_COUNT(%rbx), %rax          # n
    mov     %rax, L(%rsp)
    mov     (%rdx), %rsi                    # index
    mov     (%rcx), %rcx                    # count
    test    %rcx, %rcx
    jz      8f
    mov     %rax, %r8
    mul     %rsi
    div     %rcx
    mov     %rax, %r12                      # start = len(indices) * index // count
    lea     1(%rsi), %rax
    mul     %r8
    div     %rcx
    mov     %rax, %r13                      # end = len(indices) * (index + 1) // count
    mov     %r13, %rax
    sub     %r12, %rax
    lea     LIST_FIXED(,%rax,8), %rdx
    cmp     %rdx, LIST_SIZE(%r9)
    jb      9f
    movq    $LIST_FIXED, LIST_OFFSET(%r9)
    mov     %rax, LIST_COUNT(%r9)
    lea     LIST_FIXED(%r9), %r15
    mov     (%r14), %rax
    mov     %rax, S7(%rsp)
1:  cmp     %r13, %r12
    jae     2f
    mov     %r12, (L + 8)(%rsp)
    mov     S7(%rsp), %rax
    mov     %rax, (%r14)
    lea     (L + 8)(%rsp), %rdi             # indices[compute_shuffled_index(i, len(indices), seed)]
    lea     L(%rsp), %rsi
    mov     %rbp, %rdx
    mov     %r14, %rcx
    lea     (L + 16)(%rsp), %r8
    call    lantern_compute_shuffled_index
    test    %rax, %rax
    jnz     7f
    mov     (L + 16)(%rsp), %rax
    mov     LIST_FIXED(%rbx,%rax,8), %rax
    mov     %rax, (%r15)
    add     $8, %r15
    inc     %r12
    jmp     1b
2:  xor     %eax, %eax
7:  LEAVE 32
8:  mov     $LANTERN_INVALID_SHUFFLED_INDEX, %eax
    LEAVE 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
SPEC_END compute_committee

/*
 * rbx state, rbp slot, r12 index pointer, r13 scratch, r14 out, r15 scratch size, S7 n, S8 list.
 * Locals: L epoch, L+8 committees per slot, L+16 domain type, L+24 seed (32), L+56 index, L+64 count.
 */
SPEC_FUNCTION get_beacon_committee
    ENTER 80
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    NEED_SCRATCH %r13, %rbx, 2, 9f
    mov     (%r13), %r15
    mov     %rbp, %rax                      # epoch = compute_epoch_at_slot(slot)
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     %rax, L(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    mov     %r13, %rdx
    lea     (L + 8)(%rsp), %rcx
    call    lantern_get_committee_count_per_slot
    test    %rax, %rax
    jnz     7f
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    mov     %rcx, S7(%rsp)
    SCRATCH_LIST %rax, %r13, %r15, 0, %rcx
    mov     %rax, S8(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    mov     %rax, %rdx
    call    lantern_get_active_validator_indices
    test    %rax, %rax
    jnz     7f
    movl    $DOMAIN_BEACON_ATTESTER, (L + 16)(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 16)(%rsp), %rdx
    lea     (L + 24)(%rsp), %rcx
    call    lantern_get_seed
    test    %rax, %rax
    jnz     7f
    mov     (L + 8)(%rsp), %rcx             # index = (slot % SLOTS_PER_EPOCH) * committees_per_slot + index
    mov     %rbp, %rax
    and     $(SLOTS_PER_EPOCH - 1), %eax
    imul    %rcx, %rax
    add     (%r12), %rax
    jc      6f
    mov     %rax, (L + 56)(%rsp)
    shl     $LOG2_SLOTS_PER_EPOCH, %rcx     # count = committees_per_slot * SLOTS_PER_EPOCH
    mov     %rcx, (L + 64)(%rsp)
    mov     S7(%rsp), %rcx
    SCRATCH_GIVE %r13, %r15, 1, %rcx
    mov     S8(%rsp), %rdi
    lea     (L + 24)(%rsp), %rsi
    lea     (L + 56)(%rsp), %rdx
    lea     (L + 64)(%rsp), %rcx
    mov     %r13, %r8
    mov     %r14, %r9
    call    lantern_compute_committee
7:  LEAVE 80
6:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 80
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 80
SPEC_END get_beacon_committee

/*
 * rbx state, rbp attestation, r12 scratch, r13 out, r14 committee offset, r15 committee index cursor,
 * S7 committee, S8 committee indices.
 * Locals: L committee index, L+8 the scratch size the callee gets, L+16 bits, L+24 bit count, L+32 cursor end.
 */
SPEC_FUNCTION get_attesting_indices
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH_B %r12, %rbx, 3, CIDX_BYTES, 9f
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    lea     LIST_FIXED(,%rcx,8), %rax       # out has room for every validator
    cmp     %rax, LIST_SIZE(%r13)
    jb      9f
    mov     (%r12), %rdx
    sub     $CIDX_BYTES, %rdx
    lea     (%r12,%rdx), %rsi               # committee indices: the last CIDX_BYTES
    movq    $CIDX_BYTES, (%rsi)
    mov     %rsi, S8(%rsp)
    sub     %rax, %rdx
    lea     (%r12,%rdx), %rsi               # the committee: the L(n) before
    mov     %rax, (%rsi)
    mov     %rsi, S7(%rsp)
    mov     %rdx, (L + 8)(%rsp)
    lea     Attestation_committee_bits(%rbp), %rdi
    mov     S8(%rsp), %rsi
    call    lantern_get_committee_indices
    PART    %rax, %rcx, %rbp, Attestation_aggregation_bits
    mov     %rax, (L + 16)(%rsp)
    mov     %rcx, (L + 24)(%rsp)
    movq    $LIST_FIXED, LIST_OFFSET(%r13)
    movq    $0, LIST_COUNT(%r13)
    xor     %r14d, %r14d
    mov     S8(%rsp), %rax
    lea     LIST_FIXED(%rax), %r15
    mov     LIST_COUNT(%rax), %rcx
    lea     (%r15,%rcx,8), %rcx
    mov     %rcx, (L + 32)(%rsp)
1:  cmp     (L + 32)(%rsp), %r15
    jae     4f
    mov     (%r15), %rax
    add     $8, %r15
    mov     %rax, L(%rsp)
    mov     (L + 8)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi                      # committee = get_beacon_committee(state, data.slot, committee_index)
    lea     (Attestation_data + AttestationData_slot)(%rbp), %rsi
    lea     L(%rsp), %rdx
    mov     %r12, %rcx
    mov     S7(%rsp), %r8
    call    lantern_get_beacon_committee
    test    %rax, %rax
    jnz     7f
    mov     S7(%rsp), %rsi
    mov     LIST_COUNT(%rsi), %rcx          # members left
    add     $LIST_FIXED, %rsi
    mov     (L + 16)(%rsp), %rdi            # bits
    mov     (L + 24)(%rsp), %r8             # bit count
    mov     LIST_COUNT(%r13), %r9
    lea     LIST_FIXED(%r13,%r9,8), %rdx
2:  test    %rcx, %rcx
    jz      3f
    cmp     %r8, %r14                       # aggregation_bits[committee_offset + index]
    jae     8f
    mov     (%rsi), %rax
    add     $8, %rsi
    bt      %r14, (%rdi)
    jnc     25f
    mov     %rax, (%rdx)
    add     $8, %rdx
    inc     %r9
25: inc     %r14
    dec     %rcx
    jmp     2b
3:  mov     %r9, LIST_COUNT(%r13)
    jmp     1b
4:  lea     LIST_FIXED(%r13), %rdi          # a set: ascending
    mov     LIST_COUNT(%r13), %rsi
    call    sort_u64
    xor     %eax, %eax
7:  LEAVE 48
8:  mov     $LANTERN_INVALID_ATTESTATION, %eax
    LEAVE 48
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
SPEC_END get_attesting_indices

/* rbx state, rbp attestation, r12 scratch, r13 out, r14 scratch size, r15 the attesting list. */
SPEC_FUNCTION get_indexed_attestation
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH_B %r12, %rbx, 4, CIDX_BYTES, 9f
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    mov     (%r12), %r14
    SCRATCH_LIST %r15, %r12, %r14, 0, %rcx
    SCRATCH_GIVE %r12, %r14, 1, %rcx
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     %r15, %rcx
    call    lantern_get_attesting_indices
    test    %rax, %rax
    jnz     7f
    mov     LIST_COUNT(%r15), %rcx          # out: attesting_indices, data, signature
    lea     IndexedAttestation__fixed(,%rcx,8), %rax
    cmp     %rax, (%r13)
    jb      9f
    movq    $IndexedAttestation__fixed, IndexedAttestation_attesting_indices(%r13)
    mov     %rcx, (IndexedAttestation_attesting_indices + 8)(%r13)
    lea     IndexedAttestation__fixed(%r13), %rdi
    lea     LIST_FIXED(%r15), %rsi
    lea     (,%rcx,8), %rdx
    call    lantern_copy
    lea     IndexedAttestation_data(%r13), %rdi
    lea     Attestation_data(%rbp), %rsi
    mov     $AttestationData__mem, %edx
    call    lantern_copy
    lea     IndexedAttestation_signature(%r13), %rdi
    lea     Attestation_signature(%rbp), %rsi
    mov     $96, %edx
    call    lantern_copy
    xor     %eax, %eax
7:  LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END get_indexed_attestation

/*
 * rbx state, rbp indexed attestation, r12 scratch, r13 out, r14 indices, r15 count, S7 keys.
 * Locals: L domain type, L+8 domain (32), L+40 message (24 + 32).
 */
SPEC_FUNCTION is_valid_indexed_attestation
    ENTER 96
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    movq    $0, (%r13)
    PART    %r14, %r15, %rbp, IndexedAttestation_attesting_indices
    test    %r15, %r15                      # len(indices) == 0: False
    jz      8f
    mov     $1, %eax                        # indices sorted and unique
1:  cmp     %r15, %rax
    jae     2f
    mov     -8(%r14,%rax,8), %rcx
    cmp     %rcx, (%r14,%rax,8)
    jbe     8f
    inc     %rax
    jmp     1b
2:  mov     -8(%r14,%r15,8), %rax           # the largest index names a validator
    cmp     (BeaconState_validators + 8)(%rbx), %rax
    jae     6f
    imul    $48, %r15, %rax                 # pubkeys: a BlsPublicKeyList at the end of scratch
    add     $(24 + 7), %rax
    and     $-8, %rax
    mov     (%r12), %rcx
    MOVQ    %rdx, LANTERN_SCRATCH_FIXED
    add     %rax, %rdx
    cmp     %rdx, %rcx
    jb      9f
    sub     %rax, %rcx
    lea     (%r12,%rcx), %rdx
    mov     %rdx, S7(%rsp)
    mov     %rax, (%rdx)
    movq    $24, 8(%rdx)
    mov     %r15, 16(%rdx)
    mov     %rcx, (%r12)
    lea     24(%rdx), %rdi
    mov     BeaconState_validators(%rbx), %r8
    add     %rbx, %r8
    xor     %ecx, %ecx
3:  cmp     %r15, %rcx
    jae     4f
    mov     (%r14,%rcx,8), %rax
    shl     $7, %rax
    add     %r8, %rax
    movdqu  Validator_pubkey(%rax), %xmm0
    movdqu  (Validator_pubkey + 16)(%rax), %xmm1
    movdqu  (Validator_pubkey + 32)(%rax), %xmm2
    movdqu  %xmm0, (%rdi)
    movdqu  %xmm1, 16(%rdi)
    movdqu  %xmm2, 32(%rdi)
    add     $48, %rdi
    inc     %rcx
    jmp     3b
4:  movl    $DOMAIN_BEACON_ATTESTER, L(%rsp)    # domain = get_domain(state, DOMAIN_BEACON_ATTESTER, data.target.epoch)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    lea     (IndexedAttestation_data + AttestationData_target + Checkpoint_epoch)(%rbp), %rdx
    mov     %r12, %rcx
    lea     (L + 8)(%rsp), %r8
    call    lantern_get_domain
    test    %rax, %rax
    jnz     7f
    ADDRESS %rdi, lantern_type_AttestationData
    lea     IndexedAttestation_data(%rbp), %rsi
    lea     (L + 8)(%rsp), %rdx
    mov     %r12, %rcx
    lea     (L + 64)(%rsp), %r8
    call    lantern_compute_signing_root
    test    %rax, %rax
    jnz     7f
    movq    $56, (L + 40)(%rsp)
    movq    $24, (L + 48)(%rsp)
    movq    $32, (L + 56)(%rsp)
    mov     S7(%rsp), %rdi                  # bls.FastAggregateVerify(pubkeys, signing_root, signature)
    lea     (L + 40)(%rsp), %rsi
    lea     IndexedAttestation_signature(%rbp), %rdx
    mov     %r12, %rcx
    mov     %r13, %r8
    CALL_GLOBAL crypto_bls_fast_aggregate_verify
7:  LEAVE 96
8:  xor     %eax, %eax
    LEAVE 96
6:  mov     $LANTERN_INVALID_VALIDATOR_INDEX, %eax
    LEAVE 96
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 96
SPEC_END is_valid_indexed_attestation

/*
 * rbx state, rbp data, r12 delay, r13 out, r14 matching source, r15 matching target, S7 matching head.
 * Locals: L current epoch, L+8 target root (32), L+40 head root (32), L+72 SLOTS_PER_EPOCH, L+80 its root.
 */
SPEC_FUNCTION get_attestation_participation_flag_indices
    ENTER 96
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     (%rdx), %r12
    mov     %rcx, %r13
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     (AttestationData_target + Checkpoint_epoch)(%rbp), %rax
    lea     BeaconState_current_justified_checkpoint(%rbx), %rcx
    lea     BeaconState_previous_justified_checkpoint(%rbx), %rdx
    cmp     L(%rsp), %rax                   # justified_checkpoint
    cmovne  %rdx, %rcx
    xor     %r14d, %r14d                    # is_matching_source = data.source == justified_checkpoint
    mov     Checkpoint_epoch(%rcx), %rax
    cmp     (AttestationData_source + Checkpoint_epoch)(%rbp), %rax
    jne     1f
    lea     (AttestationData_source + Checkpoint_root)(%rbp), %rax
    add     $Checkpoint_root, %rcx
    NE32    %rax, %rcx, 1f
    mov     $1, %r14d
1:  mov     %rbx, %rdi                      # target_root = get_block_root(state, data.target.epoch)
    lea     (AttestationData_target + Checkpoint_epoch)(%rbp), %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_get_block_root
    test    %rax, %rax
    jnz     7f
    xor     %r15d, %r15d
    lea     (AttestationData_target + Checkpoint_root)(%rbp), %rax
    lea     (L + 8)(%rsp), %rcx
    NE32    %rax, %rcx, 2f
    mov     %r14, %r15                      # is_matching_target = is_matching_source and target_root_matches
2:  mov     %rbx, %rdi                      # head_root = get_block_root_at_slot(state, data.slot)
    lea     AttestationData_slot(%rbp), %rsi
    lea     (L + 40)(%rsp), %rdx
    call    lantern_get_block_root_at_slot
    test    %rax, %rax
    jnz     7f
    movq    $0, S7(%rsp)
    lea     AttestationData_beacon_block_root(%rbp), %rax
    lea     (L + 40)(%rsp), %rcx
    NE32    %rax, %rcx, 3f
    mov     %r15, S7(%rsp)
3:  mov     $LANTERN_INVALID_SOURCE, %eax   # assert is_matching_source
    test    %r14, %r14
    jz      7f
    movq    $SLOTS_PER_EPOCH, (L + 72)(%rsp)
    lea     (L + 72)(%rsp), %rdi
    lea     (L + 80)(%rsp), %rsi
    call    lantern_integer_squareroot
    movq    $LIST_FIXED, LIST_OFFSET(%r13)
    lea     LIST_FIXED(%r13), %rcx
    cmp     (L + 80)(%rsp), %r12            # source within integer_squareroot(SLOTS_PER_EPOCH)
    ja      4f
    movq    $TIMELY_SOURCE_FLAG_INDEX, (%rcx)
    add     $8, %rcx
4:  test    %r15, %r15
    jz      5f
    movq    $TIMELY_TARGET_FLAG_INDEX, (%rcx)
    add     $8, %rcx
5:  cmpq    $0, S7(%rsp)
    je      6f
    cmp     $MIN_ATTESTATION_INCLUSION_DELAY, %r12
    jne     6f
    movq    $TIMELY_HEAD_FLAG_INDEX, (%rcx)
    add     $8, %rcx
6:  lea     LIST_FIXED(%r13), %rax
    sub     %rax, %rcx
    shr     $3, %rcx
    mov     %rcx, LIST_COUNT(%r13)
    xor     %eax, %eax
7:  LEAVE 96
SPEC_END get_attestation_participation_flag_indices

/*
 * rbx state, rbp attestation, r12 scratch, r13 result, r14 committee offset then the flag index,
 * r15 committee then the attesting cursor, S7 committee indices.
 * Locals: L previous epoch, L+8 current epoch, L+16 committees per slot, L+24 committee index,
 * L+32 inclusion delay, L+40 valid, L+48 flags (FLAGS_BYTES), L+96 proposer, L+104 base reward,
 * L+112 index or cursor, L+120 proposer reward numerator, L+128 flag, L+136 cursor end, L+144 the indexed
 * attestation, L+152 the attesting list, L+160 the scratch size callees get, L+168 participation.
 */
SPEC_FUNCTION process_attestation
    ENTER 176
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rcx, %r12
    mov     %r8, %r13
    NEED_SCRATCH_B %r12, %rbx, 10, ATTEST_EXTRA, 9f
    movq    $0, (%r13)
    mov     (%r12), %rdx                    # own scratch at the end: committee indices, committee, indexed attestation, attesting
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    sub     $CIDX_BYTES, %rdx
    lea     (%r12,%rdx), %rax
    movq    $CIDX_BYTES, (%rax)
    mov     %rax, S7(%rsp)
    lea     LIST_FIXED(,%rcx,8), %rsi       # L(n)
    sub     %rsi, %rdx
    lea     (%r12,%rdx), %r15
    mov     %rsi, (%r15)
    lea     (IndexedAttestation__fixed + 8)(%rsi), %rdi
    sub     %rdi, %rdx
    lea     (%r12,%rdx), %rax
    mov     %rdi, (%rax)
    mov     %rax, (L + 144)(%rsp)
    sub     %rsi, %rdx
    lea     (%r12,%rdx), %rax
    mov     %rsi, (%rax)
    mov     %rax, (L + 152)(%rsp)
    mov     %rdx, (L + 160)(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     $LANTERN_INVALID_ATTESTATION, %eax
    mov     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%rbp), %rcx
    cmp     L(%rsp), %rcx                   # assert data.target.epoch in (previous, current)
    je      10f
    cmp     (L + 8)(%rsp), %rcx
    jne     6f
10: mov     (Attestation_data + AttestationData_slot)(%rbp), %rdx
    mov     %rdx, %rsi                      # assert data.target.epoch == compute_epoch_at_slot(data.slot)
    shr     $LOG2_SLOTS_PER_EPOCH, %rsi
    cmp     %rsi, %rcx
    jne     6f
    add     $MIN_ATTESTATION_INCLUSION_DELAY, %rdx  # assert data.slot + MIN_ATTESTATION_INCLUSION_DELAY <= state.slot
    jc      5f
    cmp     BeaconState_slot(%rbx), %rdx
    ja      6f
    cmpq    $0, (Attestation_data + AttestationData_index)(%rbp)  # assert data.index == 0
    jne     6f
    lea     Attestation_committee_bits(%rbp), %rdi
    mov     S7(%rsp), %rsi
    call    lantern_get_committee_indices
    xor     %r14d, %r14d                    # committee_offset
    mov     S7(%rsp), %rax
    lea     LIST_FIXED(%rax), %rcx
    mov     LIST_COUNT(%rax), %rdx
    lea     (%rcx,%rdx,8), %rdx
    mov     %rdx, (L + 136)(%rsp)
    mov     %rcx, (L + 112)(%rsp)           # the cursor over committee indices
1:  mov     (L + 112)(%rsp), %rax
    cmp     (L + 136)(%rsp), %rax
    jae     3f
    mov     (%rax), %rcx
    add     $8, %rax
    mov     %rax, (L + 112)(%rsp)
    mov     %rcx, (L + 24)(%rsp)
    mov     (L + 160)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi                      # assert committee_index < get_committee_count_per_slot(...)
    lea     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%rbp), %rsi
    mov     %r12, %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_get_committee_count_per_slot
    test    %rax, %rax
    jnz     7f
    mov     (L + 24)(%rsp), %rcx
    mov     $LANTERN_INVALID_ATTESTATION, %eax
    cmp     (L + 16)(%rsp), %rcx
    jae     6f
    mov     (L + 160)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi
    lea     (Attestation_data + AttestationData_slot)(%rbp), %rsi
    lea     (L + 24)(%rsp), %rdx
    mov     %r12, %rcx
    mov     %r15, %r8
    call    lantern_get_beacon_committee
    CHECK_STATUS %r13, 7f, 8f
    PART    %rsi, %rdx, %rbp, Attestation_aggregation_bits
    mov     LIST_COUNT(%r15), %rcx
    xor     %r8d, %r8d                      # committee_attesters
2:  test    %rcx, %rcx
    jz      25f
    mov     $LANTERN_INVALID_ATTESTATION, %eax  # aggregation_bits[committee_offset + index]
    cmp     %rdx, %r14
    jae     6f
    bt      %r14, (%rsi)
    adc     $0, %r8
    inc     %r14
    dec     %rcx
    jmp     2b
25: mov     $LANTERN_INVALID_ATTESTATION, %eax
    test    %r8, %r8                        # assert len(committee_attesters) > 0
    jz      6f
    jmp     1b
3:  mov     $LANTERN_INVALID_ATTESTATION, %eax  # assert len(attestation.aggregation_bits) == committee_offset
    cmp     (Attestation_aggregation_bits + 8)(%rbp), %r14
    jne     6f
    mov     BeaconState_slot(%rbx), %rax
    sub     (Attestation_data + AttestationData_slot)(%rbp), %rax
    mov     %rax, (L + 32)(%rsp)
    movq    $FLAGS_BYTES, (L + 48)(%rsp)
    mov     %rbx, %rdi                      # participation_flag_indices
    lea     Attestation_data(%rbp), %rsi
    lea     (L + 32)(%rsp), %rdx
    lea     (L + 48)(%rsp), %rcx
    call    lantern_get_attestation_participation_flag_indices
    CHECK_STATUS %r13, 7f, 8f
    mov     (L + 160)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi                      # assert is_valid_indexed_attestation(state, get_indexed_attestation(...))
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     (L + 144)(%rsp), %rcx
    call    lantern_get_indexed_attestation
    CHECK_STATUS %r13, 7f, 8f
    mov     (L + 160)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi
    mov     (L + 144)(%rsp), %rsi
    mov     %r12, %rdx
    lea     (L + 40)(%rsp), %rcx
    call    lantern_is_valid_indexed_attestation
    CHECK_STATUS %r13, 7f, 8f
    mov     $LANTERN_INVALID_ATTESTATION, %eax
    cmpq    $0, (L + 40)(%rsp)
    je      6f
    mov     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%rbp), %rax
    cmp     (L + 8)(%rsp), %rax
    jne     31f
    PART    %rax, %rcx, %rbx, BeaconState_current_epoch_participation
    jmp     32f
31: PART    %rax, %rcx, %rbx, BeaconState_previous_epoch_participation
32: mov     %rax, (L + 168)(%rsp)
    mov     (L + 160)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi                      # for index in get_attesting_indices(state, attestation)
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     (L + 152)(%rsp), %rcx
    call    lantern_get_attesting_indices
    CHECK_STATUS %r13, 7f, 8f
    movq    $0, (L + 120)(%rsp)
    mov     (L + 152)(%rsp), %rax           # the attesting list; the committee indices are done
    lea     LIST_FIXED(%rax), %r15
    mov     LIST_COUNT(%rax), %rcx
    lea     (%r15,%rcx,8), %rcx
    mov     %rcx, (L + 136)(%rsp)
4:  cmp     (L + 136)(%rsp), %r15
    jae     45f
    mov     (%r15), %rax
    add     $8, %r15
    mov     %rax, (L + 112)(%rsp)
    xor     %r14d, %r14d                    # for flag_index, weight in enumerate(PARTICIPATION_FLAG_WEIGHTS)
41: cmp     $3, %r14
    jae     4b
    mov     (L + 48 + LIST_COUNT)(%rsp), %rcx   # flag_index in participation_flag_indices
    lea     (L + 48 + LIST_FIXED)(%rsp), %rdx
42: test    %rcx, %rcx
    jz      44f
    cmp     (%rdx), %r14
    je      43f
    add     $8, %rdx
    dec     %rcx
    jmp     42b
43: mov     %r14, (L + 128)(%rsp)
    mov     (L + 168)(%rsp), %rdi           # and not has_flag(epoch_participation[index], flag_index)
    add     (L + 112)(%rsp), %rdi
    lea     (L + 128)(%rsp), %rsi
    lea     (L + 40)(%rsp), %rdx
    call    lantern_has_flag
    cmpq    $0, (L + 40)(%rsp)
    jne     44f
    mov     (L + 168)(%rsp), %rdi           # epoch_participation[index] = add_flag(...)
    add     (L + 112)(%rsp), %rdi
    lea     (L + 128)(%rsp), %rsi
    mov     %rdi, %rdx
    call    lantern_add_flag
    mov     (L + 160)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi                      # proposer_reward_numerator += get_base_reward(state, index) * weight
    lea     (L + 112)(%rsp), %rsi
    mov     %r12, %rdx
    lea     (L + 104)(%rsp), %rcx
    call    lantern_get_base_reward
    test    %rax, %rax
    jnz     7f
    mov     $TIMELY_SOURCE_WEIGHT, %eax     # the source and head weights are equal
    mov     $TIMELY_TARGET_WEIGHT, %ecx
    cmp     $TIMELY_TARGET_FLAG_INDEX, %r14
    cmove   %rcx, %rax
    imul    (L + 104)(%rsp), %rax
    add     %rax, (L + 120)(%rsp)
    jc      5f
44: inc     %r14
    jmp     41b
45: mov     (L + 120)(%rsp), %rax           # proposer_reward = numerator // proposer_reward_denominator
    mov     $((WEIGHT_DENOMINATOR - PROPOSER_WEIGHT) * WEIGHT_DENOMINATOR / PROPOSER_WEIGHT), %ecx
    xor     %edx, %edx
    div     %rcx
    mov     %rax, (L + 120)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 96)(%rsp), %rsi
    call    lantern_get_beacon_proposer_index
    mov     %rbx, %rdi
    lea     (L + 96)(%rsp), %rsi
    lea     (L + 120)(%rsp), %rdx
    call    lantern_increase_balance
8:  xor     %eax, %eax
7:  LEAVE 176
5:  mov     $LANTERN_INVALID_OVERFLOW, %eax
6:  mov     %rax, (%r13)
    xor     %eax, %eax
    LEAVE 176
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 176
SPEC_END process_attestation

.if TIMELY_SOURCE_WEIGHT != TIMELY_HEAD_WEIGHT
.error "lantern_process_attestation takes the source weight for the head flag"
.endif
