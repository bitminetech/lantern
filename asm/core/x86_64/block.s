/*
 * Block processing: the header, RANDAO, eth1 data and small helpers, x86-64.
 * Requirements: docs/reference/block-processing.md.
 */

LEAF lantern_get_beacon_proposer_index
    mov     BeaconState_slot(%rdi), %rax
    and     $(SLOTS_PER_EPOCH - 1), %eax
    mov     BeaconState_proposer_lookahead(%rdi,%rax,8), %rax
    mov     %rax, (%rsi)
    RETURN_OK
END_FUNCTION lantern_get_beacon_proposer_index

LEAF lantern_xor
    movdqu  (%rdi), %xmm0
    movdqu  (%rsi), %xmm1
    pxor    %xmm1, %xmm0
    movdqu  %xmm0, (%rdx)
    movdqu  16(%rdi), %xmm0
    movdqu  16(%rsi), %xmm1
    pxor    %xmm1, %xmm0
    movdqu  %xmm0, 16(%rdx)
    RETURN_OK
END_FUNCTION lantern_xor

/* bits rdi, length rsi (pointer to the bit count), out rdx. */
LEAF lantern_get_set_bit_count
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
END_FUNCTION lantern_get_set_bit_count

/*
 * rbx state, rbp block, r12 scratch, r13 result, r14 body.
 * Locals: L proposer index, L+8 latest header root, L+40 body root.
 */
FUNCTION lantern_process_block_header
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
    lea     L(%rsp), %rsi
    call    lantern_get_beacon_proposer_index
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
END_FUNCTION lantern_process_block_header
