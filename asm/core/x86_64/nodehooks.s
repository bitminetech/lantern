/*
 * The node's work on one fork, x86-64: decode SSZ bytes with the fork's types, then call the
 * fork's fork choice functions. lantern_node_run (node.s, in the common object) calls these
 * exports for the fork of the block or message. Requirements: docs/reference/node.md.
 */

/* The node reads the slot of a state of any fork at NODE_STATE_SLOT. */
.if BeaconState_slot - NODE_STATE_SLOT
.error "BeaconState_slot is not NODE_STATE_SLOT"
.endif

/*
 * Decode the ByteList rsi as the type rdi into the end of the scratch rdx, whose size field
 * then shrinks by the value's room: rax = 0, 1 (scratch too small) or 2 (not an encoding of
 * the type); rdx = the value. The caller restores the size field. rbx type, rbp bytes,
 * r12 scratch, r13 the value's room, r14 the value. Locals: L the size.
 */
LOCAL_FUNCTION node_decode
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    lea     L(%rsp), %rcx
    CALL_GLOBAL ssz_deserialize_size
    test    %rax, %rax
    jz      1f
    cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    je      8f
    jmp     9f
1:  mov     L(%rsp), %rax                   # the value at the end of scratch
    lea     7(%rax), %r13
    and     $-8, %r13
    mov     (%r12), %rcx
    lea     8(%r13), %rdx
    cmp     %rdx, %rcx
    jb      8f
    sub     %r13, %rcx
    lea     (%r12,%rcx), %r14
    mov     %rax, (%r14)
    mov     %rcx, (%r12)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     %r14, %rcx
    CALL_GLOBAL ssz_deserialize
    test    %rax, %rax
    jz      2f
    cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    je      8f
    jmp     9f
2:  mov     %r14, %rdx
    xor     %eax, %eax
    LEAVE 16
8:  mov     $1, %eax
    LEAVE 16
9:  mov     $2, %eax
    LEAVE 16
END_FUNCTION node_decode

.if FORK == FORK_BELLATRIX
/* rax = the PowBlock of the node rdi whose block_hash is the 32 bytes at rsi, or 0. Uses rcx, rdx, r8, r11, xmm0-xmm2. */
LOCAL_FUNCTION node_pow_block
    UNWIND_END_PROLOGUE
    PART    %rcx, %rdx, %rdi, Node_pow_blocks
1:  test    %rdx, %rdx
    jz      3f
    lea     PowBlock_block_hash(%rcx), %r8
    NE32    %r8, %rsi, 2f
    mov     %rcx, %rax
    ret
2:  add     $POW_BLOCK_BYTES, %rcx
    dec     %rdx
    jmp     1b
3:  xor     %eax, %eax
    ret
END_FUNCTION node_pow_block
.endif

/*
 * (store, node, data, state, options, scratch, result): on_block of the SignedBeaconBlock in
 * data. Bellatrix: the pow_block and pow_parent of options from the PowBlocks of the node.
 * rbx store, rbp data then the block, r12 state, r13 options, r14 scratch, r15 result, S7 node,
 * S8 the scratch size, restored on return.
 */
SPEC_FUNCTION node_import
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, S7(%rsp)
    mov     %rdx, %rbp
    mov     %rcx, %r12
    mov     %r8, %r13
    mov     %r9, %r14
    mov     (0 + 96)(%rsp), %r15            # the seventh argument
    mov     (%r14), %rax
    mov     %rax, S8(%rsp)
    movq    $0, (%r15)
    ADDRESS %rdi, lantern_type_SignedBeaconBlock
    mov     %rbp, %rsi
    mov     %r14, %rdx
    call    node_decode
    cmp     $1, %rax
    je      8f
    ja      9f
    mov     %rdx, %rbp
.if FORK == FORK_BELLATRIX
    PART    %rcx, %rax, %rbp, SignedBeaconBlock_message     # get_pow_block(payload.parent_hash) and its parent
    PART    %rdx, %rax, %rcx, BeaconBlock_body
    PART    %rcx, %rax, %rdx, BeaconBlockBody_execution_payload
    mov     S7(%rsp), %rdi
    lea     ExecutionPayload_parent_hash(%rcx), %rsi
    call    node_pow_block
    mov     %rax, BlockOptions_pow_block(%r13)
    test    %rax, %rax
    jz      1f
    mov     S7(%rsp), %rdi
    lea     PowBlock_parent_hash(%rax), %rsi
    call    node_pow_block
1:  mov     %rax, BlockOptions_pow_parent(%r13)
.endif
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    mov     %r15, %r9
    call    lantern_on_block
    jmp     99f
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    jmp     99f
9:  movq    $LANTERN_INVALID_ENCODING, (%r15)
    xor     %eax, %eax
99: mov     S8(%rsp), %rcx
    mov     %rcx, (%r14)
    LEAVE 0
SPEC_END node_import

/*
 * (data, scratch, root, result): hash_tree_root of the message of the SignedBeaconBlock in data.
 * rbp data, r12 scratch, r13 root, r14 result, S8 the scratch size, restored on return.
 */
SPEC_FUNCTION node_block_root
    ENTER 0
    mov     %rdi, %rbp
    mov     %rsi, %r12
    mov     %rdx, %r13
    mov     %rcx, %r14
    mov     (%r12), %rax
    mov     %rax, S8(%rsp)
    movq    $0, (%r14)
    ADDRESS %rdi, lantern_type_SignedBeaconBlock
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    node_decode
    cmp     $1, %rax
    je      8f
    ja      9f
    PART    %rsi, %rax, %rdx, SignedBeaconBlock_message
    ADDRESS %rdi, lantern_type_BeaconBlock
    mov     %r12, %rdx
    mov     %r13, %rcx
    CALL_GLOBAL ssz_hash_tree_root
    cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    je      8f
    jmp     99f
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    jmp     99f
9:  movq    $LANTERN_INVALID_ENCODING, (%r14)
    xor     %eax, %eax
99: mov     S8(%rsp), %rcx
    mov     %rcx, (%r12)
    LEAVE 0
SPEC_END node_block_root

/*
 * (store, data, is_from_block, state, scratch, result, target): validate_on_attestation of the
 * Attestation in data; with no target checkpoint state (state 0) the result is
 * LANTERN_NEED_TARGET_STATE and target holds the target checkpoint, else on_attestation.
 * rbx store, rbp data then the attestation, r12 is_from_block, r13 state, r14 scratch,
 * r15 result, S7 target, S8 the scratch size, restored on return.
 */
SPEC_FUNCTION node_attestation
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r9, %r15
    mov     (0 + 96)(%rsp), %rax            # the seventh argument
    mov     %rax, S7(%rsp)
    mov     (%r14), %rax
    mov     %rax, S8(%rsp)
    movq    $0, (%r15)
    ADDRESS %rdi, lantern_type_Attestation
    mov     %rbp, %rsi
    mov     %r14, %rdx
    call    node_decode
    cmp     $1, %rax
    je      8f
    ja      9f
    mov     %rdx, %rbp
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    lantern_validate_on_attestation
    test    %rax, %rax
    jz      1f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8f
    mov     %rax, (%r15)                    # a failed check
    xor     %eax, %eax
    jmp     99f
1:  test    %r13, %r13
    jnz     2f
    mov     S7(%rsp), %rdi
    mov     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%rbp), %rax
    mov     %rax, (%rdi)
    lea     (Attestation_data + AttestationData_target + Checkpoint_root)(%rbp), %rsi
    add     $8, %rdi
    COPY32  %rdi, %rsi
    movq    $LANTERN_NEED_TARGET_STATE, (%r15)
    xor     %eax, %eax
    jmp     99f
2:  mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    mov     %r15, %r9
    call    lantern_on_attestation
    jmp     99f
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    jmp     99f
9:  movq    $LANTERN_INVALID_ENCODING, (%r15)
    xor     %eax, %eax
99: mov     S8(%rsp), %rcx
    mov     %rcx, (%r14)
    LEAVE 0
SPEC_END node_attestation

/*
 * (store, data, state, scratch, result): on_attester_slashing of the AttesterSlashing in data.
 * rbx store, rbp data, r12 state, r13 scratch, r14 result, S8 the scratch size, restored on return.
 */
SPEC_FUNCTION node_attester_slashing
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     (%r13), %rax
    mov     %rax, S8(%rsp)
    movq    $0, (%r14)
    ADDRESS %rdi, lantern_type_AttesterSlashing
    mov     %rbp, %rsi
    mov     %r13, %rdx
    call    node_decode
    cmp     $1, %rax
    je      8f
    ja      9f
    mov     %rbx, %rdi
    mov     %rdx, %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    call    lantern_on_attester_slashing
    jmp     99f
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    jmp     99f
9:  movq    $LANTERN_INVALID_ENCODING, (%r14)
    xor     %eax, %eax
99: mov     S8(%rsp), %rcx
    mov     %rcx, (%r13)
    LEAVE 0
SPEC_END node_attester_slashing
