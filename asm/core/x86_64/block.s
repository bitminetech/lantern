/*
 * Block processing: the header, RANDAO, eth1 data and small helpers, x86-64.
 * Requirements: docs/reference/block-processing.md.
 */

.if FORK >= FORK_FULU
SPEC_LEAF get_beacon_proposer_index
    mov     BeaconState_slot(%rdi), %rax
    and     $(SLOTS_PER_EPOCH - 1), %eax
    mov     BeaconState_proposer_lookahead(%rdi,%rax,8), %rax
    mov     %rax, (%rsi)
    RETURN_OK
SPEC_END get_beacon_proposer_index
.else
/*
 * Before fulu: (state, scratch, out), with scratch S(2).
 * rbx state, rbp scratch, r12 out, r13 scratch size, r14 indices.
 * Locals: L epoch, L+8 domain type, L+16 the message (seed 32, slot 8), L+56 seed (32).
 */
SPEC_FUNCTION get_beacon_proposer_index
    ENTER 96
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    NEED_SCRATCH %rbp, %rbx, 2, 9f
    mov     (%rbp), %r13
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    movl    $DOMAIN_BEACON_PROPOSER, (L + 8)(%rsp)
    mov     %rbx, %rdi                      # seed = hash(get_seed(state, epoch, DOMAIN_BEACON_PROPOSER) + uint_to_bytes(state.slot))
    lea     L(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_get_seed
    test    %rax, %rax
    jnz     7f
    mov     BeaconState_slot(%rbx), %rax
    mov     %rax, (L + 48)(%rsp)
    lea     (L + 16)(%rsp), %rdi
    mov     $40, %esi
    lea     (L + 56)(%rsp), %rdx
    call    sha256_short
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    SCRATCH_LIST %r14, %rbp, %r13, 0, %rcx  # indices: the last list
    mov     %rbx, %rdi                      # indices = get_active_validator_indices(state, epoch)
    lea     L(%rsp), %rsi
    mov     %r14, %rdx
    call    lantern_get_active_validator_indices
    test    %rax, %rax
    jnz     7f
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    SCRATCH_GIVE %rbp, %r13, 1, %rcx
    mov     %rbx, %rdi                      # compute_proposer_index(state, indices, seed)
    mov     %r14, %rsi
    lea     (L + 56)(%rsp), %rdx
    mov     %rbp, %rcx
    mov     %r12, %r8
    call    lantern_compute_proposer_index
7:  LEAVE 96
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 96
SPEC_END get_beacon_proposer_index
.endif

SPEC_LEAF xor
    movdqu  (%rdi), %xmm0
    movdqu  (%rsi), %xmm1
    pxor    %xmm1, %xmm0
    movdqu  %xmm0, (%rdx)
    movdqu  16(%rdi), %xmm0
    movdqu  16(%rsi), %xmm1
    pxor    %xmm1, %xmm0
    movdqu  %xmm0, 16(%rdx)
    RETURN_OK
SPEC_END xor

/* bits rdi, length rsi (pointer to the bit count), out rdx. */
SPEC_LEAF get_set_bit_count
    mov     (%rsi), %rsi
    xor     %eax, %eax                      # count
    xor     %ecx, %ecx                      # bit
1:  cmp     %rsi, %rcx
    jae     2f
    bt      %rcx, (%rdi)
    adc     $0, %rax
    inc     %rcx
    jmp     1b
2:  mov     %rax, (%rdx)
    RETURN_OK
SPEC_END get_set_bit_count

/*
 * rbx state, rbp block, r12 scratch, r13 result, r14 body.
 * Locals: L proposer index, L+8 latest header root, L+40 body root.
 */
SPEC_FUNCTION process_block_header
    ENTER 80
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rcx, %r12
    mov     %r8, %r13
    mov     BeaconBlock_slot(%rbp), %rcx
    mov     $LANTERN_INVALID_BLOCK_SLOT, %eax   # assert block.slot == state.slot
    cmp     BeaconState_slot(%rbx), %rcx
    jne     6f
    mov     $LANTERN_INVALID_BLOCK_OLDER, %eax  # assert block.slot > state.latest_block_header.slot
    cmp     (BeaconState_latest_block_header + BeaconBlockHeader_slot)(%rbx), %rcx
    jbe     6f
    mov     %rbx, %rdi
.if FORK >= FORK_FULU
    lea     L(%rsp), %rsi
    call    lantern_get_beacon_proposer_index
.else
    mov     %r12, %rsi
    lea     L(%rsp), %rdx
    call    lantern_get_beacon_proposer_index
    test    %rax, %rax
    jz      3f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      7f
    jmp     6f
3:
.endif
    mov     BeaconBlock_proposer_index(%rbp), %rcx
    mov     $LANTERN_INVALID_PROPOSER_INDEX, %eax   # assert block.proposer_index == get_beacon_proposer_index(state)
    cmp     L(%rsp), %rcx
    jne     6f
    ADDRESS %rdi, lantern_type_BeaconBlockHeader
    lea     BeaconState_latest_block_header(%rbx), %rsi
    mov     %r12, %rdx
    lea     (L + 8)(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    lea     BeaconBlock_parent_root(%rbp), %rcx # assert block.parent_root == hash_tree_root(latest header)
    lea     (L + 8)(%rsp), %rdx
    mov     $LANTERN_INVALID_PARENT_ROOT, %eax
    NE32    %rcx, %rdx, 6f
    PART    %r14, %rax, %rbp, BeaconBlock_body
    ADDRESS %rdi, lantern_type_BeaconBlockBody
    mov     %r14, %rsi
    mov     %r12, %rdx
    lea     (L + 40)(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    lea     BeaconState_latest_block_header(%rbx), %rcx     # the new latest_block_header
    mov     BeaconBlock_slot(%rbp), %rax
    mov     %rax, BeaconBlockHeader_slot(%rcx)
    mov     BeaconBlock_proposer_index(%rbp), %rax
    mov     %rax, BeaconBlockHeader_proposer_index(%rcx)
    lea     BeaconBlockHeader_parent_root(%rcx), %rdx
    lea     BeaconBlock_parent_root(%rbp), %rax
    COPY32  %rdx, %rax
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, BeaconBlockHeader_state_root(%rcx)
    movdqu  %xmm0, (BeaconBlockHeader_state_root + 16)(%rcx)
    lea     BeaconBlockHeader_body_root(%rcx), %rdx
    lea     (L + 40)(%rsp), %rax
    COPY32  %rdx, %rax
    mov     BeaconBlock_proposer_index(%rbp), %rcx  # assert not proposer.slashed
    mov     $LANTERN_INVALID_VALIDATOR_INDEX, %eax
    cmp     (BeaconState_validators + 8)(%rbx), %rcx
    jae     6f
    VALIDATOR %rdx, %rbx, %rcx
    mov     $LANTERN_INVALID_PROPOSER_SLASHED, %eax
    cmpb    $0, Validator_slashed(%rdx)
    jne     6f
    movq    $0, (%r13)
    xor     %eax, %eax
7:  LEAVE 80
6:  mov     %rax, (%r13)
    xor     %eax, %eax
    LEAVE 80
SPEC_END process_block_header
