/*
 * The node's work on one fork, x86-64: decode SSZ bytes with the fork's types, then call the
 * fork's fork choice functions. lantern_node_run (node.s, in the common object) calls these
 * exports for the fork of the block or message. Requirements: docs/reference/node.md.
 */

/* The node reads the slot of a state of any fork at NODE_STATE_SLOT. */
.if BeaconState_slot - NODE_STATE_SLOT
.error "BeaconState_slot is not NODE_STATE_SLOT"
.endif
.if BeaconState_current_justified_checkpoint - BeaconState_previous_justified_checkpoint - 40 || BeaconState_finalized_checkpoint - BeaconState_current_justified_checkpoint - 40
.error "the checkpoints of BeaconState do not follow each other"
.endif
.if BeaconState_latest_block_header - NODE_STATE_HEADER || BeaconBlock_state_root - NODE_BLOCK_STATE_ROOT
.error "BeaconState_latest_block_header or BeaconBlock_state_root is not the common offset"
.endif
.if BeaconState_genesis_validators_root - NODE_STATE_GVR
.error "BeaconState_genesis_validators_root is not NODE_STATE_GVR"
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
 * (data, scratch, root, result, blobs): hash_tree_root of the message of the SignedBeaconBlock in
 * data, and the length of its body's blob_kzg_commitments (0 before deneb). rbp data, r12
 * scratch, r13 root, r14 result, r15 blobs, S8 the scratch size, restored on return.
 */
SPEC_FUNCTION node_block_root
    ENTER 0
    mov     %rdi, %rbp
    mov     %rsi, %r12
    mov     %rdx, %r13
    mov     %rcx, %r14
    mov     %r8, %r15
    mov     (%r12), %rax
    mov     %rax, S8(%rsp)
    movq    $0, (%r14)
    movq    $0, (%r15)
    ADDRESS %rdi, lantern_type_SignedBeaconBlock
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    node_decode
    cmp     $1, %rax
    je      8f
    ja      9f
    PART    %rsi, %rax, %rdx, SignedBeaconBlock_message
.if FORK >= FORK_DENEB
    PART    %rcx, %rax, %rsi, BeaconBlock_body
    mov     (BeaconBlockBody_blob_kzg_commitments + 8)(%rcx), %rax
    mov     %rax, (%r15)
.endif
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
 * (data, scratch, root) -> status: hash_tree_root of the AttestationData at data, its 128 SSZ
 * bytes, into root. scratch for ssz_hash_tree_root.
 */
SPEC_FUNCTION node_data_root
    FRAME 0
    mov     %rdx, %rcx
    mov     %rsi, %rdx
    mov     %rdi, %rsi
    ADDRESS %rdi, lantern_type_AttestationData
    CALL_GLOBAL ssz_hash_tree_root
    cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    jne     1f
    mov     $LANTERN_BUFFER_TOO_SMALL, %eax
1:  UNFRAME 0
SPEC_END node_data_root
.if AttestationData__mem != 128 || AttestationData__ssz != 128
.error "node_data_root: an AttestationData value is its 128 SSZ bytes"
.endif

/*
 * (data, scratch, out): the SignedBeaconBlockHeader of the SignedBeaconBlock in data: the message's
 * slot, proposer_index, parent_root, state_root, hash_tree_root of its body, and the signature.
 * rbp data, r12 scratch, r13 out, r14 the block, r15 its message, S8 the scratch size, restored.
 */
SPEC_FUNCTION node_block_header
    ENTER 0
    mov     %rdi, %rbp
    mov     %rsi, %r12
    mov     %rdx, %r13
    mov     (%r12), %rax
    mov     %rax, S8(%rsp)
    ADDRESS %rdi, lantern_type_SignedBeaconBlock
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    node_decode
    cmp     $1, %rax
    je      8f
    ja      9f
    mov     %rdx, %r14
    PART    %r15, %rax, %r14, SignedBeaconBlock_message
    mov     BeaconBlock_slot(%r15), %rax
    mov     %rax, (%r13)
    mov     BeaconBlock_proposer_index(%r15), %rax
    mov     %rax, 8(%r13)
    lea     16(%r13), %rdi
    lea     BeaconBlock_parent_root(%r15), %rsi
    mov     $32, %edx
    call    lantern_copy
    lea     48(%r13), %rdi
    lea     BeaconBlock_state_root(%r15), %rsi
    mov     $32, %edx
    call    lantern_copy
    lea     112(%r13), %rdi
    lea     SignedBeaconBlock_signature(%r14), %rsi
    mov     $96, %edx
    call    lantern_copy
    PART    %rsi, %rax, %r15, BeaconBlock_body  # body_root
    ADDRESS %rdi, lantern_type_BeaconBlockBody
    mov     %r12, %rdx
    lea     80(%r13), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     8f
    xor     %eax, %eax
    jmp     99f
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    jmp     99f
9:  mov     $LANTERN_INVALID_ENCODING, %eax
99: mov     S8(%rsp), %rcx
    mov     %rcx, (%r12)
    LEAVE 0
SPEC_END node_block_header

/* (state, out): the previous_justified, current_justified and finalized checkpoints of the state. */
SPEC_FUNCTION node_state_checkpoints
    FRAME 0
    lea     BeaconState_previous_justified_checkpoint(%rdi), %rax
    mov     %rsi, %rdi
    mov     %rax, %rsi
    mov     $(3 * 40), %edx
    call    lantern_copy
    xor     %eax, %eax
    UNFRAME 0
SPEC_END node_state_checkpoints

/*
 * (state, config, scratch, out): lantern_node_proposers (node.md): the dependent root of the epoch
 * of the state's slot, then its proposers. rbx state, rbp config, r12 scratch, r13 out, r15 the
 * scratch size, restored. Locals: L the epoch, L+8 the slot - 1, L+16 the latest_block_header (112).
 */
SPEC_FUNCTION node_proposers
    ENTER 128
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     (%r12), %r15
    mov     $LANTERN_INVALID_SLOT, %eax
    testq   $(SLOTS_PER_EPOCH - 1), BeaconState_slot(%rbx)
    jnz     99f
    NEED_SCRATCH %r12, %rbx, 2, 8f
    mov     BeaconState_slot(%rbx), %rax
    mov     %rax, %rcx
    shr     $LOG2_SLOTS_PER_EPOCH, %rcx
    mov     %rcx, L(%rsp)
    test    %rax, %rax
    jz      2f
    dec     %rax                            /* get_block_root_at_slot(state, slot - 1) */
    mov     %rax, (L + 8)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    mov     %r13, %rdx
    call    lantern_get_block_root_at_slot
    test    %rax, %rax
    jnz     99f
    jmp     3f
2:  lea     (L + 16)(%rsp), %rdi            /* slot 0: hash_tree_root of the latest_block_header, its state_root the state's when zero */
    lea     BeaconState_latest_block_header(%rbx), %rsi
    mov     $BeaconBlockHeader__mem, %edx
    call    lantern_copy
    mov     (L + 16 + BeaconBlockHeader_state_root)(%rsp), %rax
    or      (L + 16 + BeaconBlockHeader_state_root + 8)(%rsp), %rax
    or      (L + 16 + BeaconBlockHeader_state_root + 16)(%rsp), %rax
    or      (L + 16 + BeaconBlockHeader_state_root + 24)(%rsp), %rax
    jnz     21f
    mov     %rbx, %rdi
    mov     CONFIG_STATE_CACHE(%rbp), %rsi
    mov     %r12, %rdx
    lea     (L + 16 + BeaconBlockHeader_state_root)(%rsp), %rcx
    call    lantern_state_root
    test    %rax, %rax
    jnz     99f
21: ADDRESS %rdi, lantern_type_BeaconBlockHeader
    lea     (L + 16)(%rsp), %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     8f
3:
.if FORK >= FORK_FULU
    lea     32(%r13), %rdi                  /* the proposers: the first SLOTS_PER_EPOCH of proposer_lookahead */
    lea     BeaconState_proposer_lookahead(%rbx), %rsi
    mov     $(8 * SLOTS_PER_EPOCH), %edx
    call    lantern_copy
    mov     (BeaconState_validators + 8)(%rbx), %rcx    /* each names a validator */
    xor     %edx, %edx
    mov     $LANTERN_INVALID_VALIDATOR_INDEX, %eax
4:  cmp     %rcx, 32(%r13,%rdx,8)
    jae     99f
    inc     %rdx
    cmp     $SLOTS_PER_EPOCH, %rdx
    jb      4b
    xor     %eax, %eax
.else
    mov     %rbx, %rdi                      /* the proposers: get_beacon_proposer_indices of the epoch */
    lea     L(%rsp), %rsi
    mov     %r12, %rdx
    lea     32(%r13), %rcx
    call    lantern_get_beacon_proposer_indices
.endif
    jmp     99f
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
99: mov     %r15, (%r12)
    LEAVE 128
SPEC_END node_proposers

/*
 * (state, config, scratch, out): lantern_node_event_roots (node.md): the block root, the state root,
 * and the previous and current duty dependent roots of a block's post-state. rbx state, rbp config,
 * r12 scratch, r13 out, r14 which dependent root, r15 the scratch size, restored. Locals: L a slot,
 * L+8 its place, L+16 the latest_block_header (112).
 */
SPEC_FUNCTION node_event_roots
    ENTER 128
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     (%r12), %r15
    NEED_SCRATCH %r12, %rbx, 2, 8f
    lea     (L + 16)(%rsp), %rdi            # the header, its state_root the state's when zero
    lea     BeaconState_latest_block_header(%rbx), %rsi
    mov     $BeaconBlockHeader__mem, %edx
    call    lantern_copy
    mov     (L + 16 + BeaconBlockHeader_state_root)(%rsp), %rax
    or      (L + 16 + BeaconBlockHeader_state_root + 8)(%rsp), %rax
    or      (L + 16 + BeaconBlockHeader_state_root + 16)(%rsp), %rax
    or      (L + 16 + BeaconBlockHeader_state_root + 24)(%rsp), %rax
    jnz     1f
    mov     %rbx, %rdi
    mov     CONFIG_STATE_CACHE(%rbp), %rsi
    mov     %r12, %rdx
    lea     (L + 16 + BeaconBlockHeader_state_root)(%rsp), %rcx
    call    lantern_state_root
    test    %rax, %rax
    jnz     99f
1:  lea     32(%r13), %rdi
    lea     (L + 16 + BeaconBlockHeader_state_root)(%rsp), %rsi
    COPY32  %rdi, %rsi
    ADDRESS %rdi, lantern_type_BeaconBlockHeader    # the block root
    lea     (L + 16)(%rsp), %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     8f
    xor     %r14d, %r14d                    # each dependent root: of the epoch before the state's (0), then of its epoch (1)
2:  mov     BeaconState_slot(%rbx), %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    add     %r14, %rax
    mov     %r14, %rcx
    shl     $5, %rcx
    lea     64(%r13,%rcx), %rcx
    mov     %rcx, (L + 8)(%rsp)
    cmp     $2, %rax                        # get_block_root_at_slot(state, compute_start_slot_at_epoch(e) - 1), e = rax - 1
    jb      3f
    dec     %rax
    shl     $LOG2_SLOTS_PER_EPOCH, %rax
    dec     %rax
    mov     %rax, L(%rsp)
    jmp     31f
3:  cmpq    $0, BeaconState_slot(%rbx)      # on underflow, the genesis block root
    je      32f
    movq    $0, L(%rsp)
31: mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    mov     (L + 8)(%rsp), %rdx
    call    lantern_get_block_root_at_slot
    test    %rax, %rax
    jnz     99f
    jmp     4f
32: mov     (L + 8)(%rsp), %rdi
    COPY32  %rdi, %r13
4:  inc     %r14
    cmp     $2, %r14
    jb      2b
    xor     %eax, %eax
    jmp     99f
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
99: mov     %r15, (%r12)
    LEAVE 128
SPEC_END node_event_roots

.if BeaconState_state_roots != NODE_STATE_STATE_ROOTS || BeaconState_fork != NODE_STATE_FORK
.error "nodehooks: NODE_STATE_STATE_ROOTS or NODE_STATE_FORK is not the state's"
.endif
.if BeaconState_validators != NODE_STATE_VALIDATORS || BeaconState_balances != NODE_STATE_BALANCES || Validator__mem != NODE_VALIDATOR_MEM
.error "nodehooks: NODE_STATE_VALIDATORS, NODE_STATE_BALANCES or NODE_VALIDATOR_MEM is not the state's"
.endif
.if Validator_withdrawal_credentials != NODE_VALIDATOR_CREDENTIALS || Validator_effective_balance != NODE_VALIDATOR_EFFECTIVE_BALANCE || Validator_slashed != NODE_VALIDATOR_SLASHED
.error "nodehooks: a NODE_VALIDATOR_* offset is not the Validator's"
.endif
.if Validator_activation_eligibility_epoch != NODE_VALIDATOR_ELIGIBILITY || Validator_activation_epoch != NODE_VALIDATOR_ACTIVATION || Validator_exit_epoch != NODE_VALIDATOR_EXIT || Validator_withdrawable_epoch != NODE_VALIDATOR_WITHDRAWABLE
.error "nodehooks: a NODE_VALIDATOR_* epoch offset is not the Validator's"
.endif

/*
 * (state, config, index, scratch, out) -> rax: the AttestationData of the state's slot, its 128 SSZ
 * bytes in out (node.md, lantern_node_attestation_data). rbx the state, r12 the index, r13 out.
 * Locals: L lantern_node_event_roots's out (128).
 */
SPEC_FUNCTION node_attestation_data
    ENTER 128
    mov     %rdi, %rbx
    mov     %rdx, %r12
    mov     %r8, %r13
    mov     %rcx, %rdx
    lea     L(%rsp), %rcx
    call    lantern_node_event_roots
    test    %rax, %rax
    jnz     9f
    mov     BeaconState_slot(%rbx), %rax    # slot, index
    mov     %rax, (%r13)
.if FORK >= FORK_ELECTRA
    xor     %r12d, %r12d
.endif
    mov     %r12, 8(%r13)
    lea     16(%r13), %rdi                  # beacon_block_root
    lea     L(%rsp), %rsi
    mov     $32, %edx
    call    lantern_copy
    lea     48(%r13), %rdi                  # source: current_justified_checkpoint
    lea     BeaconState_current_justified_checkpoint(%rbx), %rsi
    mov     $40, %edx
    call    lantern_copy
    mov     BeaconState_slot(%rbx), %rax    # target: the epoch, and its boundary block's root
    mov     %rax, %rcx
    shr     $LOG2_SLOTS_PER_EPOCH, %rcx
    mov     %rcx, 88(%r13)
    shl     $LOG2_SLOTS_PER_EPOCH, %rcx
    lea     L(%rsp), %rsi
    cmp     %rax, %rcx
    je      1f
    and     $(SLOTS_PER_HISTORICAL_ROOT - 1), %ecx
    shl     $5, %rcx
    lea     BeaconState_block_roots(%rbx,%rcx), %rsi
1:  lea     96(%r13), %rdi
    mov     $32, %edx
    call    lantern_copy
    xor     %eax, %eax
9:  LEAVE 128
SPEC_END node_attestation_data

/*
 * (state, config, ids, scratch, out) -> rax: the committee assignments of the ids in the epoch of
 * the state at its first slot (node.md, lantern_node_attester_duties). rbx the state, rbp the
 * config, r12 the items, r13 scratch, r14 out, r15 the items' count; S7 a bit for each validator an
 * item names and S8 a committee's list, both at the end of scratch; S9 a member's place. Locals: L
 * the epoch, L+8 the committees at a slot, L+16 the validators, L+24 the scratch's size, L+32 a
 * slot, L+40 a committee index, L+64 lantern_node_event_roots's out (128).
 */
SPEC_FUNCTION node_attester_duties
    ENTER 192
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     8(%rdx), %r12
    add     %rdx, %r12
    mov     16(%rdx), %r15
    shr     $6, %r15
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     BeaconState_slot(%rbx), %rax    # the first slot of an epoch
    test    $(SLOTS_PER_EPOCH - 1), %eax
    jnz     95f
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     %rax, L(%rsp)
    mov     (%r13), %rax
    mov     %rax, (L + 24)(%rsp)
    mov     %rbx, %rdi                      # the dependent root: the previous duty dependent root
    mov     %rbp, %rsi
    mov     %r13, %rdx
    lea     (L + 64)(%rsp), %rcx
    call    lantern_node_event_roots
    test    %rax, %rax
    jnz     99f
    mov     %r14, %rdi
    lea     (L + 128)(%rsp), %rsi
    mov     $32, %edx
    call    lantern_copy
    mov     %rbx, %rdi                      # the committees at a slot
    lea     L(%rsp), %rsi
    mov     CONFIG_COMMITTEE_CACHE(%rbp), %rdx
    mov     %r13, %rcx
    lea     (L + 8)(%rsp), %r8
    call    lantern_get_committee_count_per_slot
    test    %rax, %rax
    jnz     99f
    mov     (L + 8)(%rsp), %rax
    mov     %rax, 32(%r14)
    lea     40(%r14), %rdi                  # no assignment yet
    imul    $48, %r15, %rsi
    call    lantern_zero
    mov     (BeaconState_validators + 8)(%rbx), %rax    # the bits and a committee's list at the end of scratch, S(2) before them
    mov     %rax, (L + 16)(%rsp)
    lea     63(%rax), %rcx
    shr     $6, %rcx
    shl     $3, %rcx
    mov     (L + 8)(%rsp), %rsi
    imul    $SLOTS_PER_EPOCH, %rsi, %rsi
    xor     %edx, %edx
    div     %rsi
    lea     1(%rax), %rdx
    shl     $3, %rdx
    add     $LIST_FIXED, %rdx
    lea     (%rcx,%rdx), %r8
    mov     (L + 16)(%rsp), %rax
    shl     $3, %rax
    add     $LIST_FIXED, %rax
    shl     $1, %rax
    add     $LANTERN_SCRATCH_FIXED, %rax
    add     %r8, %rax
    mov     (%r13), %r9
    cmp     %rax, %r9
    jb      97f
    sub     %r8, %r9
    mov     %r9, (%r13)
    lea     (%r13,%r9), %rdi
    mov     %rdi, S7(%rsp)
    lea     (%rdi,%rcx), %rax
    mov     %rax, S8(%rsp)
    mov     %rdx, (%rax)
    movq    $LIST_FIXED, LIST_OFFSET(%rax)
    movq    $0, LIST_COUNT(%rax)
    mov     %rcx, %rsi
    call    lantern_zero
    xor     %ecx, %ecx                      # a bit for each item's index
1:  cmp     %r15, %rcx
    jae     2f
    mov     %rcx, %rax
    shl     $6, %rax
    mov     8(%r12,%rax), %rax
    cmp     (L + 16)(%rsp), %rax
    jae     11f
    mov     S7(%rsp), %rdx
    bts     %rax, (%rdx)
11: inc     %rcx
    jmp     1b
2:  mov     L(%rsp), %rax                   # each committee of each slot of the epoch
    shl     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     %rax, (L + 32)(%rsp)
3:  movq    $0, (L + 40)(%rsp)
4:  mov     %rbx, %rdi
    lea     (L + 32)(%rsp), %rsi
    lea     (L + 40)(%rsp), %rdx
    mov     CONFIG_COMMITTEE_CACHE(%rbp), %rcx
    mov     %r13, %r8
    mov     S8(%rsp), %r9
    call    lantern_get_beacon_committee
    test    %rax, %rax
    jnz     98f
    movq    $0, S9(%rsp)
5:  mov     S9(%rsp), %rcx
    mov     S8(%rsp), %rdx
    cmp     LIST_COUNT(%rdx), %rcx
    jae     7f
    mov     LIST_FIXED(%rdx,%rcx,8), %rax   # a member an item names: each such item's assignment
    mov     S7(%rsp), %rsi
    bt      %rax, (%rsi)
    jnc     6f
    xor     %r8d, %r8d
51: cmp     %r15, %r8
    jae     6f
    mov     %r8, %r9
    shl     $6, %r9
    cmp     8(%r12,%r9), %rax
    jne     52f
    imul    $48, %r8, %r9
    lea     40(%r14,%r9), %r9
    movq    $1, (%r9)
    mov     (L + 32)(%rsp), %r10
    mov     %r10, 8(%r9)
    mov     (L + 40)(%rsp), %r10
    mov     %r10, 16(%r9)
    mov     LIST_COUNT(%rdx), %r10
    mov     %r10, 24(%r9)
    mov     %rcx, 32(%r9)
    mov     %rax, 40(%r9)
52: inc     %r8
    jmp     51b
6:  incq    S9(%rsp)
    jmp     5b
7:  mov     (L + 40)(%rsp), %rax            # the next committee, then the next slot
    inc     %rax
    mov     %rax, (L + 40)(%rsp)
    cmp     (L + 8)(%rsp), %rax
    jb      4b
    mov     (L + 32)(%rsp), %rax
    inc     %rax
    mov     %rax, (L + 32)(%rsp)
    test    $(SLOTS_PER_EPOCH - 1), %eax
    jnz     3b
    xor     %eax, %eax
98: mov     (L + 24)(%rsp), %rcx
    mov     %rcx, (%r13)
99: LEAVE 192
95: mov     $LANTERN_INVALID_SLOT, %eax
    LEAVE 192
97: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 192
SPEC_END node_attester_duties

/*
 * (state, out) -> rax: the block number and hash of the state's latest_execution_payload_header
 * (node.md, lantern_node_payload_parent).
 */
SPEC_FUNCTION node_payload_parent
    ENTER 0
.if FORK < FORK_BELLATRIX
    mov     $LANTERN_INVALID_EVENT, %eax
.else
    MOVQ    %rax, BeaconState_latest_execution_payload_header   # the header value in its part
    add     (%rdi,%rax), %rdi
    MOVQ    %rax, ExecutionPayloadHeader_block_number
    mov     (%rdi,%rax), %rax
    mov     %rax, (%rsi)
    MOVQ    %rax, ExecutionPayloadHeader_block_hash
    add     %rax, %rdi
    xchg    %rdi, %rsi
    add     $8, %rdi
    mov     $32, %edx
    call    lantern_copy
    xor     %eax, %eax
.endif
    LEAVE 0
SPEC_END node_payload_parent

/*
 * (ssz, scratch, out) -> rax: the block root of a sidecar's SSZ bytes, hash_tree_root of its
 * signed_block_header.message (node.md, lantern_node_sidecar_root). rbx the bytes, r12 their count.
 */
SPEC_FUNCTION node_sidecar_root
    ENTER 0
.if FORK < FORK_DENEB
    mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 0
.else
    mov     8(%rdi), %rbx
    add     %rdi, %rbx
    mov     16(%rdi), %r12
    mov     %rsi, %r13
    mov     %rdx, %r14
.if FORK < FORK_FULU
    MOVQ    %rax, PUB_BLOB_SIDECAR          # a BlobSidecar: its fixed size; the header after the index, blob, commitment and proof
    cmp     %rax, %r12
    jne     8f
    lea     (8 + PUB_BLOB_BYTES + 96)(%rbx), %rsi
.else
    cmp     $PUB_COLUMN_FIXED, %r12         # a DataColumnSidecar: the header after the index and three offsets
    jb      8f
    lea     20(%rbx), %rsi
.endif
    ADDRESS %rdi, lantern_type_BeaconBlockHeader
    mov     %r13, %rdx
    mov     %r14, %rcx
    CALL_GLOBAL ssz_hash_tree_root
    LEAVE 0
8:  mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 0
.endif
SPEC_END node_sidecar_root

/* Set the byte of each index of a phase0 epoch list of PendingAttestation values: of the part at ref of the state. */
.macro LIVE_PENDING ref
    MOVQ    %rax, \ref
    mov     (%rbx,%rax), %rcx               # the part's offset and count
    mov     8(%rbx,%rax), %rdx
    mov     %rcx, (L + 16)(%rsp)
    mov     %rdx, (L + 24)(%rsp)
71: mov     (L + 16)(%rsp), %rcx
    mov     (L + 24)(%rsp), %rdx
    test    %rdx, %rdx
    jz      74f
    mov     (%rbx,%rcx), %rax               # the next value starts after this one's size
    add     %rcx, %rax
    mov     %rax, (L + 16)(%rsp)
    dec     %rdx
    mov     %rdx, (L + 24)(%rsp)
    mov     S10(%rsp), %rax                 # the bytes and the indices at the end, S(4) before them
    SCRATCH_GIVE %r13, %rax, 2, %r15
    mov     %rbx, %rdi
    lea     (%rbx,%rcx), %rsi
    mov     (L + 32)(%rsp), %rdx
    mov     %r13, %rcx
    mov     S10(%rsp), %rax
    SCRATCH_LIST %r8, %r13, %rax, 1, %r15
    call    lantern_get_attesting_indices
    mov     S10(%rsp), %rcx
    mov     %rcx, (%r13)
    test    %rax, %rax
    jnz     99f
    mov     S10(%rsp), %rax
    SCRATCH_LIST %rdi, %r13, %rax, 1, %r15
    mov     LIST_COUNT(%rdi), %rcx
    add     $LIST_FIXED, %rdi
72: test    %rcx, %rcx
    jz      71b
    mov     (%rdi), %rax
    movb    $1, (%r14,%rax)
    add     $8, %rdi
    dec     %rcx
    jmp     72b
74:
.endm

/* Set the byte of each validator whose participation flags, of the part at ref of the state, are not 0. */
.macro LIVE_FLAGS ref
    PART    %rsi, %rcx, %rbx, \ref
    cmp     %r15, %rcx
    cmova   %r15, %rcx
    xor     %eax, %eax
75: cmp     %rcx, %rax
    jae     77f
    cmpb    $0, (%rsi,%rax)
    je      76f
    movb    $1, (%r14,%rax)
76: inc     %rax
    jmp     75b
77:
.endm

/*
 * (state, config, seen, ids, epoch, scratch, out) -> rax: whether the validator of each item was
 * seen live in the epoch (node.md, lantern_node_liveness). rbx the state, rbp the seen, r12 the
 * items, r13 scratch, r14 a byte for each validator (list 0 of scratch), r15 the validator count;
 * S7 out, S8 the items' count, S9 the epoch, S10 the scratch's size. Locals: L the previous epoch,
 * L+8 the current epoch, L+16 the next value and the count left of an epoch list, L+32 the
 * CommitteeCache.
 */
SPEC_FUNCTION node_liveness
    ENTER 48
    mov     %rdi, %rbx
    mov     CONFIG_COMMITTEE_CACHE(%rsi), %rax
    mov     %rax, (L + 32)(%rsp)
    mov     %rdx, %rbp
    mov     8(%rcx), %r12
    add     %rcx, %r12
    mov     16(%rcx), %rax
    shr     $6, %rax
    mov     %rax, S8(%rsp)
    mov     %r8, S9(%rsp)
    mov     %r9, %r13
    mov     (48 + 96)(%rsp), %rax           # the seventh argument
    mov     %rax, S7(%rsp)
.if FORK == FORK_PHASE0
    NEED_SCRATCH %r13, %rbx, 6, 98f
.else
    NEED_SCRATCH %r13, %rbx, 1, 98f
.endif
    mov     (BeaconState_validators + 8)(%rbx), %r15
    mov     (%r13), %rax
    mov     %rax, S10(%rsp)
    SCRATCH_LIST %r14, %r13, %rax, 0, %r15
    add     $LIST_FIXED, %r14               # a byte for each validator, 0
    mov     %r14, %rdi
    mov     %r15, %rsi
    call    lantern_zero
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     S9(%rsp), %rax                  # in the beacon chain: the current epoch's list
    cmp     (L + 8)(%rsp), %rax
    jne     1f
.if FORK == FORK_PHASE0
    LIVE_PENDING BeaconState_current_epoch_attestations
.else
    LIVE_FLAGS BeaconState_current_epoch_participation
.endif
1:  mov     S9(%rsp), %rax                  # the previous epoch's list
    cmp     L(%rsp), %rax
    jne     2f
.if FORK == FORK_PHASE0
    LIVE_PENDING BeaconState_previous_epoch_attestations
.else
    LIVE_FLAGS BeaconState_previous_epoch_participation
.endif
2:  PART    %rsi, %rcx, %rbp, Seen_keys     # on the network and from the API: the Seen's keys
    mov     S9(%rsp), %r8
3:  test    %rcx, %rcx
    jz      6f
    mov     (%rsi), %rax                    # kind, a, b: the index
    mov     8(%rsi), %rdx
    mov     16(%rsi), %rdi
    add     $SeenKey__mem, %rsi
    dec     %rcx
    cmp     %r15, %rdi
    jae     3b
    cmp     $SEEN_ATTESTATION, %rax         # an epoch's keys
    je      4f
    cmp     $SEEN_AGGREGATOR_EPOCH, %rax
    je      4f
    cmp     $SEEN_PROPOSER_SLOT, %rax       # a slot's keys
    je      31f
    cmp     $SEEN_SYNC_MESSAGE, %rax
    je      31f
    cmp     $SEEN_SYNC_CONTRIBUTION, %rax
    jne     3b
31: shr     $LOG2_SLOTS_PER_EPOCH, %rdx
4:  cmp     %r8, %rdx
    jne     3b
    movb    $1, (%r14,%rdi)
    jmp     3b
6:  xor     %ecx, %ecx                      # each item: the byte of its index
    mov     S7(%rsp), %rdi
7:  cmp     S8(%rsp), %rcx
    jae     8f
    mov     %rcx, %rax
    shl     $6, %rax
    mov     8(%r12,%rax), %rax
    xor     %edx, %edx
    cmp     %r15, %rax
    jae     79f
    movzbl  (%r14,%rax), %edx
79: mov     %dl, (%rdi,%rcx)
    inc     %rcx
    jmp     7b
8:  xor     %eax, %eax
99: mov     S10(%rsp), %rcx
    mov     %rcx, (%r13)
    LEAVE 48
98: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
SPEC_END node_liveness

/* ---------------------------------------------------------------- Rewards (beacon-api.md, getBlockRewards) */

.if FORK >= FORK_ALTAIR
/*
 * (state rdi, scratch rsi) -> rax status, rdx participant_reward, rcx proposer_reward of
 * process_sync_aggregate at the state (altair beacon-chain.md). Locals: 0 the total active
 * balance, 8 the base reward per increment, 16 the state, 24 the scratch.
 */
LOCAL_FUNCTION node_sync_values
    FRAME 32
    mov     %rdi, 16(%rsp)
    mov     %rsi, 24(%rsp)
    mov     %rsp, %rdx
    call    lantern_get_total_active_balance
    test    %rax, %rax
    jnz     9f
    mov     16(%rsp), %rdi
    mov     24(%rsp), %rsi
    lea     8(%rsp), %rdx
    call    lantern_get_base_reward_per_increment
    test    %rax, %rax
    jnz     9f
    mov     (%rsp), %rax
    xor     %edx, %edx
    MOVQ    %rcx, EFFECTIVE_BALANCE_INCREMENT
    div     %rcx                            # total_active_increments
    imul    8(%rsp), %rax                   # total_base_rewards
    imul    $SYNC_REWARD_WEIGHT, %rax, %rax
    shr     $6, %rax                        # // WEIGHT_DENOMINATOR
    shr     $LOG2_SLOTS_PER_EPOCH, %rax     # max_participant_rewards
    xor     %edx, %edx
    mov     $SYNC_COMMITTEE_SIZE, %ecx
    div     %rcx                            # participant_reward
    mov     %rax, %r8
    imul    $PROPOSER_WEIGHT, %rax, %rax
    xor     %edx, %edx
    mov     $(WEIGHT_DENOMINATOR - PROPOSER_WEIGHT), %ecx
    div     %rcx                            # proposer_reward
    mov     %rax, %rcx
    mov     %r8, %rdx
    xor     %eax, %eax
9:  UNFRAME 32
END_FUNCTION node_sync_values
.endif

.if FORK == FORK_PHASE0
.if BASE_REWARDS_PER_EPOCH != 4 || PROPOSER_REWARD_QUOTIENT != 8
.error "lantern_node_block_rewards divides by BASE_REWARDS_PER_EPOCH and PROPOSER_REWARD_QUOTIENT with shifts"
.endif
/*
 * Of the E at st (k 1: early, its delays at r14 + 2n; k 2: late, at r14 + 3n): the square root of
 * its total active balance at root, and for each attestation of its previous_epoch_attestations each
 * attesting index below n takes the attestation's inclusion_delay when that is lower.
 */
.macro REWARD_LOWEST st, k, root
    mov     \st, %rax
    test    %rax, %rax
    jz      39f
    mov     S10(%rsp), %rcx
    SCRATCH_GIVE %r13, %rcx, 2, %r15
    mov     \st, %rdi
    mov     %r13, %rsi
    lea     (L + 120)(%rsp), %rdx
    call    lantern_get_total_active_balance
    mov     S10(%rsp), %rcx
    mov     %rcx, (%r13)
    test    %rax, %rax
    jnz     99f
    lea     (L + 120)(%rsp), %rdi
    lea     \root(%rsp), %rsi
    call    lantern_integer_squareroot
    mov     \st, %rdi
    MOVQ    %rax, BeaconState_previous_epoch_attestations
    mov     (%rdi,%rax), %rcx               # the part's offset and count
    mov     8(%rdi,%rax), %rdx
    mov     %rcx, (L + 16)(%rsp)
    mov     %rdx, (L + 24)(%rsp)
32: mov     (L + 16)(%rsp), %rcx
    mov     (L + 24)(%rsp), %rdx
    test    %rdx, %rdx
    jz      39f
    mov     \st, %rdi
    mov     (%rdi,%rcx), %rax               # the next value starts after this one's size
    add     %rcx, %rax
    mov     %rax, (L + 16)(%rsp)
    dec     %rdx
    mov     %rdx, (L + 24)(%rsp)
    lea     (%rdi,%rcx), %rsi
    mov     %rsi, (L + 128)(%rsp)
    mov     S10(%rsp), %rax
    SCRATCH_GIVE %r13, %rax, 2, %r15
    mov     (L + 96)(%rsp), %rdx
    mov     %r13, %rcx
    mov     S10(%rsp), %rax
    SCRATCH_LIST %r8, %r13, %rax, 1, %r15
    call    lantern_get_attesting_indices
    mov     S10(%rsp), %rcx
    mov     %rcx, (%r13)
    test    %rax, %rax
    jnz     99f
    mov     (L + 128)(%rsp), %rsi
    mov     PendingAttestation_inclusion_delay(%rsi), %r9
.if \k == 1
    lea     (%r14,%r15,2), %rdi
.else
    lea     (%r15,%r15,2), %rdi
    add     %r14, %rdi
.endif
    mov     S10(%rsp), %rax
    SCRATCH_LIST %rsi, %r13, %rax, 1, %r15
    mov     LIST_COUNT(%rsi), %rcx
    add     $LIST_FIXED, %rsi
33: test    %rcx, %rcx
    jz      32b
    mov     (%rsi), %rax
    add     $8, %rsi
    dec     %rcx
    cmp     %r15, %rax
    jae     33b
    movzbl  (%rdi,%rax), %edx
    cmp     %rdx, %r9
    jae     33b
    mov     %r9b, (%rdi,%rax)
    jmp     33b
39:
.endm
.endif

/*
 * (pre, block, early, late, config, scratch, out) -> rax: the proposer's rewards of the block on
 * its pre-state, part by part (node.md, lantern_node_block_rewards). rbx pre, rbp the body, r12
 * config, r13 scratch, r14 the bytes of the validators (list 0: the slashed marks at 0; from altair
 * the copies of the previous and current participation at n and 2n; in phase0 the rewarded marks
 * at n, bit 0 for the epoch before the block's and bit 1 for its own, and the lowest delays of
 * early and late at 2n and 3n), r15 the validator count n; S7 out, S8 early, S9 late, S10 the
 * scratch's size after the decoded block. Locals: L the scratch's size on entry, L+8 the epoch,
 * L+16 the next entry of a list and L+24 the count left, L+32 the base reward per increment
 * (phase0: the square root of early's total active balance, L+40 of late's), L+48 the flags
 * (FLAGS_BYTES), L+96 the CommitteeCache, L+104 the inclusion delay, L+112 EFFECTIVE_BALANCE_INCREMENT,
 * L+120 a value, L+128 the attestation, L+136 its E, L+144 its lowest delays, L+152 its bit.
 */
SPEC_FUNCTION node_block_rewards
    ENTER 160
    mov     %rdi, %rbx
    mov     %rdx, S8(%rsp)
    mov     %rcx, S9(%rsp)
    mov     %r8, %r12
    mov     %r9, %r13
    mov     (160 + 96)(%rsp), %rax          # the seventh argument
    mov     %rax, S7(%rsp)
    mov     (%r13), %rax
    mov     %rax, L(%rsp)
    mov     CONFIG_COMMITTEE_CACHE(%r12), %rax
    mov     %rax, (L + 96)(%rsp)
    ADDRESS %rdi, lantern_type_SignedBeaconBlock
    mov     %r13, %rdx
    call    node_decode                     # rsi: the block
    cmp     $1, %rax
    je      97f
    ja      96f
    PART    %rsi, %rcx, %rdx, SignedBeaconBlock_message
    mov     BeaconBlock_slot(%rsi), %rax
    cmp     BeaconState_slot(%rbx), %rax
    jne     95f
    PART    %rbp, %rcx, %rsi, BeaconBlock_body
    mov     BeaconBlock_proposer_index(%rsi), %rax
    mov     %rax, (L + 120)(%rsp)
    mov     (%r13), %rax
    mov     %rax, S10(%rsp)
    NEED_SCRATCH %r13, %rbx, 6, 97f
.if FORK == FORK_PHASE0
    mov     S8(%rsp), %rax
    test    %rax, %rax
    jz      1f
    NEED_SCRATCH %r13, %rax, 6, 97f
1:  mov     S9(%rsp), %rax
    test    %rax, %rax
    jz      2f
    NEED_SCRATCH %r13, %rax, 6, 97f
2:
.endif
    mov     S7(%rsp), %rdi                  # out: the proposer, then 0
    mov     (L + 120)(%rsp), %rax
    mov     %rax, (%rdi)
    xor     %eax, %eax
    mov     %rax, 8(%rdi)
    mov     %rax, 16(%rdi)
    mov     %rax, 24(%rdi)
    mov     %rax, 32(%rdi)
    mov     %rax, 40(%rdi)
    mov     (BeaconState_validators + 8)(%rbx), %r15
    mov     S10(%rsp), %rax
    SCRATCH_LIST %r14, %r13, %rax, 0, %r15
    add     $LIST_FIXED, %r14
    mov     %r14, %rdi
    lea     (,%r15,4), %rsi
    call    lantern_zero
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_current_epoch
    PART    %rsi, %rcx, %rbp, BeaconBlockBody_proposer_slashings   # proposer_slashings: each whistleblower_reward
    PART    %r8, %r10, %rbx, BeaconState_validators
    mov     S7(%rsp), %r9
    MOVQ    %r11, FORK_WHISTLEBLOWER_REWARD_QUOTIENT
3:  test    %rcx, %rcx
    jz      4f
    mov     (ProposerSlashing_signed_header_1 + SignedBeaconBlockHeader_message + BeaconBlockHeader_proposer_index)(%rsi), %rdi
    cmp     %r15, %rdi
    jae     96f
    mov     %rdi, %rax
    shl     $7, %rax
    mov     Validator_effective_balance(%r8,%rax), %rax
    xor     %edx, %edx
    div     %r11
    add     %rax, 32(%r9)
    movb    $1, (%r14,%rdi)
    add     $ProposerSlashing__mem, %rsi
    dec     %rcx
    jmp     3b
4:  PART    %rsi, %rcx, %rbp, BeaconBlockBody_attester_slashings   # attester_slashings: those process_attester_slashing slashes
    mov     %rsi, (L + 16)(%rsp)
    mov     %rcx, (L + 24)(%rsp)
5:  mov     (L + 16)(%rsp), %rsi
    mov     (L + 24)(%rsp), %rcx
    test    %rcx, %rcx
    jz      10f
    mov     (%rsi), %rax
    add     %rsi, %rax
    mov     %rax, (L + 16)(%rsp)
    dec     %rcx
    mov     %rcx, (L + 24)(%rsp)
    PART    %rdi, %rax, %rsi, AttesterSlashing_attestation_1
    PART    %r8, %rax, %rdi, IndexedAttestation_attesting_indices
    lea     (%r8,%rax,8), %r9
    PART    %rdi, %rax, %rsi, AttesterSlashing_attestation_2
    PART    %r10, %rax, %rdi, IndexedAttestation_attesting_indices
    lea     (%r10,%rax,8), %r11
6:  cmp     %r9, %r8                        # the sorted intersection, by merge
    jae     5b
    cmp     %r11, %r10
    jae     5b
    mov     (%r8), %rax
    mov     (%r10), %rdx
    cmp     %rdx, %rax
    jb      61f
    ja      62f
    add     $8, %r8
    add     $8, %r10
    cmp     %r15, %rax
    jae     96f
    cmpb    $0, (%r14,%rax)                 # an earlier slashing of the body slashed it
    jne     6b
    mov     BeaconState_validators(%rbx), %rdi  # is_slashable_validator(validator, epoch)
    add     %rbx, %rdi
    mov     %rax, %rcx
    shl     $7, %rcx
    add     %rcx, %rdi
    cmpb    $0, Validator_slashed(%rdi)
    jne     6b
    mov     (L + 8)(%rsp), %rdx
    cmp     Validator_activation_epoch(%rdi), %rdx
    jb      6b
    cmp     Validator_withdrawable_epoch(%rdi), %rdx
    jae     6b
    movb    $1, (%r14,%rax)
    mov     Validator_effective_balance(%rdi), %rax
    xor     %edx, %edx
    MOVQ    %rcx, FORK_WHISTLEBLOWER_REWARD_QUOTIENT
    div     %rcx
    mov     S7(%rsp), %rcx
    add     %rax, 40(%rcx)
    jmp     6b
61: add     $8, %r8
    jmp     6b
62: add     $8, %r10
    jmp     6b
10:
.if FORK >= FORK_ALTAIR
    mov     S10(%rsp), %rax                 # sync_aggregate: the set bits times proposer_reward
    SCRATCH_GIVE %r13, %rax, 2, %r15
    mov     %rbx, %rdi
    mov     %r13, %rsi
    call    node_sync_values
    mov     S10(%rsp), %r8
    mov     %r8, (%r13)
    test    %rax, %rax
    jnz     99f
    MOVQ    %rsi, BeaconBlockBody_sync_aggregate + SyncAggregate_sync_committee_bits
    add     %rbp, %rsi
    xor     %eax, %eax
    mov     $(SYNC_COMMITTEE_SIZE / 8), %r8d
11: test    %r8, %r8
    jz      13f
    movzbl  (%rsi), %r9d
12: test    %r9, %r9
    jz      121f
    lea     -1(%r9), %r10
    and     %r10, %r9
    inc     %rax
    jmp     12b
121: inc    %rsi
    dec     %r8
    jmp     11b
13: imul    %rcx, %rax
    mov     S7(%rsp), %rdi
    mov     %rax, 24(%rdi)
    PART    %rsi, %rdx, %rbx, BeaconState_previous_epoch_participation  # copies of the flags
    cmp     %r15, %rdx
    cmova   %r15, %rdx
    lea     (%r14,%r15), %rdi
    call    lantern_copy
    PART    %rsi, %rdx, %rbx, BeaconState_current_epoch_participation
    cmp     %r15, %rdx
    cmova   %r15, %rdx
    lea     (%r14,%r15,2), %rdi
    call    lantern_copy
    mov     S10(%rsp), %rax
    SCRATCH_GIVE %r13, %rax, 2, %r15
    mov     %rbx, %rdi
    mov     %r13, %rsi
    lea     (L + 32)(%rsp), %rdx
    call    lantern_get_base_reward_per_increment
    mov     S10(%rsp), %rcx
    mov     %rcx, (%r13)
    test    %rax, %rax
    jnz     99f
    MOVQ    %rax, EFFECTIVE_BALANCE_INCREMENT
    mov     %rax, (L + 112)(%rsp)
    PART    %rsi, %rcx, %rbp, BeaconBlockBody_attestations   # attestations: process_attestation's proposer_reward of each
    mov     %rsi, (L + 16)(%rsp)
    mov     %rcx, (L + 24)(%rsp)
20: mov     (L + 16)(%rsp), %rsi
    mov     (L + 24)(%rsp), %rcx
    test    %rcx, %rcx
    jz      90f
    mov     %rsi, (L + 128)(%rsp)
    mov     (%rsi), %rax
    add     %rsi, %rax
    mov     %rax, (L + 16)(%rsp)
    dec     %rcx
    mov     %rcx, (L + 24)(%rsp)
    mov     BeaconState_slot(%rbx), %rax
    sub     (Attestation_data + AttestationData_slot)(%rsi), %rax
    mov     %rax, (L + 104)(%rsp)
    movq    $FLAGS_BYTES, (L + 48)(%rsp)
    mov     %rbx, %rdi
    lea     Attestation_data(%rsi), %rsi
    lea     (L + 104)(%rsp), %rdx
    lea     (L + 48)(%rsp), %rcx
    call    lantern_get_attestation_participation_flag_indices
    test    %rax, %rax
    jnz     99f
    mov     S10(%rsp), %rax
    SCRATCH_GIVE %r13, %rax, 2, %r15
    mov     %rbx, %rdi
    mov     (L + 128)(%rsp), %rsi
    mov     (L + 96)(%rsp), %rdx
    mov     %r13, %rcx
    mov     S10(%rsp), %rax
    SCRATCH_LIST %r8, %r13, %rax, 1, %r15
    call    lantern_get_attesting_indices
    mov     S10(%rsp), %rcx
    mov     %rcx, (%r13)
    test    %rax, %rax
    jnz     99f
    mov     (L + 128)(%rsp), %rsi           # the copy of the target epoch's flags
    mov     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%rsi), %rax
    lea     (%r14,%r15,2), %rdi
    cmp     (L + 8)(%rsp), %rax
    je      21f
    lea     (%r14,%r15), %rdi
21: mov     (L + 48 + LIST_COUNT)(%rsp), %rcx   # the flags as bits
    lea     (L + 48 + LIST_FIXED)(%rsp), %rsi
    xor     %r8d, %r8d
22: test    %rcx, %rcx
    jz      23f
    mov     (%rsi), %rax
    bts     %rax, %r8
    add     $8, %rsi
    dec     %rcx
    jmp     22b
23: mov     S10(%rsp), %rax
    SCRATCH_LIST %rsi, %r13, %rax, 1, %r15
    mov     LIST_COUNT(%rsi), %rcx
    add     $LIST_FIXED, %rsi
    xor     %r10d, %r10d                    # proposer_reward_numerator
    PART    %r9, %rax, %rbx, BeaconState_validators
24: test    %rcx, %rcx
    jz      29f
    mov     (%rsi), %rax
    add     $8, %rsi
    dec     %rcx
    cmp     %r15, %rax
    jae     96f
    movzbl  (%rdi,%rax), %edx
    mov     %edx, %r11d
    not     %r11
    and     %r8, %r11                       # the flags it takes now
    jz      24b
    or      %r11b, (%rdi,%rax)
    shl     $7, %rax
    mov     Validator_effective_balance(%r9,%rax), %rax
    xor     %edx, %edx
    divq    (L + 112)(%rsp)
    imul    (L + 32)(%rsp), %rax            # get_base_reward(state, index)
    xor     %edx, %edx
    test    $(1 << TIMELY_SOURCE_FLAG_INDEX), %r11
    jz      25f
    add     $TIMELY_SOURCE_WEIGHT, %rdx
25: test    $(1 << TIMELY_TARGET_FLAG_INDEX), %r11
    jz      26f
    add     $TIMELY_TARGET_WEIGHT, %rdx
26: test    $(1 << TIMELY_HEAD_FLAG_INDEX), %r11
    jz      27f
    add     $TIMELY_HEAD_WEIGHT, %rdx
27: imul    %rdx, %rax
    add     %rax, %r10
    jmp     24b
29: mov     %r10, %rax
    xor     %edx, %edx
    mov     $((WEIGHT_DENOMINATOR - PROPOSER_WEIGHT) * WEIGHT_DENOMINATOR / PROPOSER_WEIGHT), %ecx
    div     %rcx
    mov     S7(%rsp), %rdx
    add     %rax, 16(%rdx)
    jmp     20b
.else
    lea     (%r14,%r15,2), %rdi             # the lowest delays of early and late: none yet
    lea     (,%r15,2), %rcx
    mov     $255, %al
    rep stosb
    REWARD_LOWEST S8(%rsp), 1, (L + 32)
    REWARD_LOWEST S9(%rsp), 2, (L + 40)
    PART    %rsi, %rcx, %rbp, BeaconBlockBody_attestations   # attestations: the proposer rewards of get_inclusion_delay_deltas
    mov     %rsi, (L + 16)(%rsp)
    mov     %rcx, (L + 24)(%rsp)
40: mov     (L + 16)(%rsp), %rsi
    mov     (L + 24)(%rsp), %rcx
    test    %rcx, %rcx
    jz      90f
    mov     %rsi, (L + 128)(%rsp)
    mov     (%rsi), %rax
    add     %rsi, %rax
    mov     %rax, (L + 16)(%rsp)
    dec     %rcx
    mov     %rcx, (L + 24)(%rsp)
    mov     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%rsi), %rdx
    cmp     (L + 8)(%rsp), %rdx
    je      41f
    lea     1(%rdx), %rax
    cmp     (L + 8)(%rsp), %rax
    jne     95f
    mov     S8(%rsp), %r8                   # the epoch before the block's: early
    lea     (%r14,%r15,2), %r9
    mov     $1, %r10d
    jmp     42f
41: mov     S9(%rsp), %r8                   # the block's epoch: late
    lea     (%r15,%r15,2), %r9
    add     %r14, %r9
    mov     $2, %r10d
42: test    %r8, %r8
    jnz     43f
    lea     1(%rdx), %rax                   # no E: the epoch after the target's is altair's or later
    cmp     CONFIG_ALTAIR_FORK_EPOCH(%r12), %rax
    jb      95f
    jmp     40b
43: lea     2(%rdx), %rax                   # E at the last slot of the epoch after the target's
    shl     $LOG2_SLOTS_PER_EPOCH, %rax
    dec     %rax
    cmp     BeaconState_slot(%r8), %rax
    jne     95f
    mov     %r8, (L + 136)(%rsp)
    mov     %r9, (L + 144)(%rsp)
    mov     %r10, (L + 152)(%rsp)
    mov     BeaconState_slot(%rbx), %rax
    sub     (Attestation_data + AttestationData_slot)(%rsi), %rax
    mov     %rax, (L + 104)(%rsp)
    mov     S10(%rsp), %rax
    SCRATCH_GIVE %r13, %rax, 2, %r15
    mov     %rbx, %rdi
    mov     (L + 96)(%rsp), %rdx
    mov     %r13, %rcx
    mov     S10(%rsp), %rax
    SCRATCH_LIST %r8, %r13, %rax, 1, %r15
    call    lantern_get_attesting_indices
    mov     S10(%rsp), %rcx
    mov     %rcx, (%r13)
    test    %rax, %rax
    jnz     99f
    mov     S10(%rsp), %rax
    SCRATCH_LIST %rsi, %r13, %rax, 1, %r15
    mov     LIST_COUNT(%rsi), %rcx
    add     $LIST_FIXED, %rsi
    mov     (L + 32)(%rsp), %r11            # the square root of E's total active balance
    cmpq    $1, (L + 152)(%rsp)
    je      45f
    mov     (L + 40)(%rsp), %r11
45: mov     (L + 136)(%rsp), %r8
    PART    %rdi, %r10, %r8, BeaconState_validators
    lea     (%r14,%r15), %r8                # the rewarded marks
    mov     (L + 144)(%rsp), %r9
44: test    %rcx, %rcx
    jz      40b
    mov     (%rsi), %rax
    add     $8, %rsi
    dec     %rcx
    cmp     %r15, %rax
    jae     96f
    movzbl  (%r8,%rax), %edx
    test    (L + 152)(%rsp), %dl
    jnz     44b
    or      (L + 152)(%rsp), %dl
    mov     %dl, (%r8,%rax)
    cmp     %r10, %rax
    jae     96f
    mov     %rax, %rdx
    shl     $7, %rdx
    cmpb    $0, Validator_slashed(%rdi,%rdx)    # unslashed in E
    jne     44b
    movzbl  (%r9,%rax), %eax                # and no attestation of E with a lower delay
    cmp     (L + 104)(%rsp), %rax
    jb      44b
    mov     Validator_effective_balance(%rdi,%rdx), %rax
    imul    $BASE_REWARD_FACTOR, %rax, %rax
    xor     %edx, %edx
    div     %r11
    shr     $2, %rax                        # get_base_reward(E, index): // BASE_REWARDS_PER_EPOCH
    shr     $3, %rax                        # // PROPOSER_REWARD_QUOTIENT
    mov     S7(%rsp), %rdx
    add     %rax, 16(%rdx)
    jmp     44b
.endif
90: mov     S7(%rsp), %rdi                  # total
    mov     16(%rdi), %rax
    add     24(%rdi), %rax
    add     32(%rdi), %rax
    add     40(%rdi), %rax
    mov     %rax, 8(%rdi)
    xor     %eax, %eax
99: mov     L(%rsp), %rcx
    mov     %rcx, (%r13)
    LEAVE 160
95: mov     $LANTERN_INVALID_SLOT, %eax
    jmp     99b
96: mov     $LANTERN_INVALID_ENCODING, %eax
    jmp     99b
97: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    jmp     99b
SPEC_END node_block_rewards

.if FORK >= FORK_ALTAIR
/*
 * rax = the entry of the validator rdi among the rdx entries of 24 bytes at rsi (index, balance,
 * member), a new one with its balance in the state rcx and member 0 when there is none, rdx = the
 * count; rax = 0 for an index past the validators. Uses r8-r10.
 */
LOCAL_FUNCTION node_reward_entry
    UNWIND_END_PROLOGUE
    mov     %rsi, %rax
    mov     %rdx, %r8
1:  test    %r8, %r8
    jz      2f
    cmp     %rdi, (%rax)
    je      3f
    add     $24, %rax
    dec     %r8
    jmp     1b
2:  PART    %r9, %r10, %rcx, BeaconState_balances
    cmp     %r10, %rdi
    jae     4f
    mov     (%r9,%rdi,8), %r9
    mov     %rdi, (%rax)
    mov     %r9, 8(%rax)
    movq    $0, 16(%rax)
    inc     %rdx
3:  ret
4:  xor     %eax, %eax
    ret
END_FUNCTION node_reward_entry

.set SYNC_REWARD_EXTRA, 8 * SYNC_COMMITTEE_SIZE + SYNC_TABLE_BYTES + 24   /* the places, the table of find_pubkeys and its 3 words */
.if 24 * (SYNC_COMMITTEE_SIZE + 1) > SYNC_TABLE_BYTES
.error "lantern_node_sync_rewards keeps its entries where the table of find_pubkeys was"
.endif

/*
 * (pre, block, scratch, out) -> rax: the balance changes of the block's sync aggregate on its
 * pre-state (node.md, lantern_node_sync_rewards). rbx pre, rbp the bits, r12 out, r13 scratch, r14
 * the places' validator indices (at the end of scratch, before the decoded block), r15 the hash
 * table of find_pubkeys, then the entries of node_reward_entry. Locals: L the scratch's size on
 * entry, L+8 the proposer rewards it took, L+16 the entries' count, L+24 participant_reward, L+32
 * proposer_reward, L+40 the proposer, L+48 the place.
 */
SPEC_FUNCTION node_sync_rewards
    ENTER 64
    mov     %rdi, %rbx
    mov     %rdx, %r13
    mov     %rcx, %r12
    mov     (%r13), %rax
    mov     %rax, L(%rsp)
    MOVQ    %rax, 24 + 16 * SYNC_COMMITTEE_SIZE
    cmp     %rax, (%r12)
    jb      97f
    ADDRESS %rdi, lantern_type_SignedBeaconBlock
    mov     %r13, %rdx
    call    node_decode                     # rsi: the block
    cmp     $1, %rax
    je      97f
    ja      96f
    PART    %rsi, %rcx, %rdx, SignedBeaconBlock_message
    mov     BeaconBlock_slot(%rsi), %rax
    cmp     BeaconState_slot(%rbx), %rax
    jne     95f
    mov     BeaconBlock_proposer_index(%rsi), %rax
    mov     %rax, (L + 40)(%rsp)
    PART    %rbp, %rcx, %rsi, BeaconBlock_body
    MOVQ    %rax, BeaconBlockBody_sync_aggregate + SyncAggregate_sync_committee_bits
    add     %rax, %rbp
    NEED_SCRATCH_B %r13, %rbx, 1, SYNC_REWARD_EXTRA, 97f
    mov     (%r13), %rax                    # the places, then the table, at the end
    MOVQ    %rcx, 8 * SYNC_COMMITTEE_SIZE
    sub     %rcx, %rax
    lea     (%r13,%rax), %r14
    MOVQ    %rcx, SYNC_TABLE_BYTES + 24
    sub     %rcx, %rax
    lea     (%r13,%rax), %r15
    mov     %rax, (%r13)                    # what callees get
    mov     %rbx, %rdi                      # committee_indices, as process_sync_aggregate finds them
    MOVQ    %rsi, BeaconState_current_sync_committee + SyncCommittee_pubkeys
    add     %rbx, %rsi
    mov     %r14, %rdx
    mov     %r15, %rcx
    call    find_pubkeys
    test    %rax, %rax
    jnz     96f
    mov     %rbx, %rdi
    mov     %r13, %rsi
    call    node_sync_values
    test    %rax, %rax
    jnz     99f
    mov     %rdx, (L + 24)(%rsp)
    mov     %rcx, (L + 32)(%rsp)
    xor     %eax, %eax
    mov     %rax, (L + 8)(%rsp)
    mov     %rax, (L + 16)(%rsp)
    mov     %rax, (L + 48)(%rsp)
1:  mov     (L + 48)(%rsp), %rcx            # each place, in order
    cmp     $SYNC_COMMITTEE_SIZE, %rcx
    jae     5f
    mov     (%r14,%rcx,8), %rdi
    mov     %r15, %rsi
    mov     (L + 16)(%rsp), %rdx
    mov     %rbx, %rcx
    call    node_reward_entry
    mov     %rdx, (L + 16)(%rsp)
    test    %rax, %rax
    jz      96f
    movq    $1, 16(%rax)                    # a member
    mov     (L + 48)(%rsp), %rcx
    mov     %rcx, %rdx
    shr     $3, %rdx
    movzbl  (%rbp,%rdx), %edx
    and     $7, %ecx
    shr     %cl, %edx
    test    $1, %dl
    jz      3f
    mov     (L + 24)(%rsp), %rcx            # the participant takes participant_reward, the proposer proposer_reward
    add     %rcx, 8(%rax)
    mov     (L + 40)(%rsp), %rdi
    mov     %r15, %rsi
    mov     (L + 16)(%rsp), %rdx
    mov     %rbx, %rcx
    call    node_reward_entry
    mov     %rdx, (L + 16)(%rsp)
    test    %rax, %rax
    jz      96f
    mov     (L + 32)(%rsp), %rcx
    add     %rcx, 8(%rax)
    add     %rcx, (L + 8)(%rsp)
    jmp     4f
3:  mov     8(%rax), %rdx                   # decrease_balance: down to 0 at the least
    sub     (L + 24)(%rsp), %rdx
    jae     31f
    xor     %edx, %edx
31: mov     %rdx, 8(%rax)
4:  incq    (L + 48)(%rsp)
    jmp     1b
5:  PART    %r8, %rcx, %rbx, BeaconState_balances   # the members in index order: the lowest after the last
    xor     %r9d, %r9d                      # 1 once one is written
    xor     %r10d, %r10d                    # the last written
    lea     24(%r12), %r11
6:  mov     $-1, %rax
    xor     %edx, %edx
    mov     %r15, %rsi
    mov     (L + 16)(%rsp), %rcx
7:  test    %rcx, %rcx
    jz      9f
    mov     (%rsi), %rdi
    cmpq    $0, 16(%rsi)
    je      8f
    test    %r9, %r9
    jz      71f
    cmp     %r10, %rdi
    jbe     8f
71: cmp     %rax, %rdi
    jae     8f
    mov     %rdi, %rax
    mov     %rsi, %rdx
8:  add     $24, %rsi
    dec     %rcx
    jmp     7b
9:  test    %rdx, %rdx
    jz      11f
    mov     8(%rdx), %rcx                   # after less before
    sub     (%r8,%rax,8), %rcx
    cmp     (L + 40)(%rsp), %rax
    jne     10f
    sub     (L + 8)(%rsp), %rcx             # the proposer: less the proposer rewards
10: mov     %rax, (%r11)
    mov     %rcx, 8(%r11)
    add     $16, %r11
    mov     $1, %r9d
    mov     %rax, %r10
    jmp     6b
11: mov     %r11, %rax
    sub     %r12, %rax
    sub     $24, %rax
    movq    $24, 8(%r12)
    mov     %rax, 16(%r12)
    xor     %eax, %eax
99: mov     L(%rsp), %rcx
    mov     %rcx, (%r13)
    LEAVE 64
95: mov     $LANTERN_INVALID_SLOT, %eax
    jmp     99b
96: mov     $LANTERN_INVALID_ENCODING, %eax
    jmp     99b
97: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    jmp     99b
SPEC_END node_sync_rewards
.else
/* (pre, block, scratch, out) -> LANTERN_NO_STATE_ANSWER: phase0 has no sync committee (node.md, lantern_node_sync_rewards). */
SPEC_FUNCTION node_sync_rewards
    FRAME 0
    mov     $LANTERN_NO_STATE_ANSWER, %eax
    UNFRAME 0
SPEC_END node_sync_rewards
.endif

/* ---------------------------------------------------------------- Attestation rewards (beacon-api.md, getAttestationsRewards) */

.if FORK >= FORK_ALTAIR
/* The participating balance of the flag at the epoch (a memory operand) into out (a memory operand): get_total_balance of the unslashed participating indices. */
.macro TOTALS_FLAG flag, epoch, out
    movq    $\flag, (L+8)(%rsp)
    mov     S7(%rsp), %rax
    SCRATCH_GIVE %r12, %rax, 1, %r15
    mov     %rbx, %rdi
    lea     (L+8)(%rsp), %rsi
    lea     \epoch, %rdx
    mov     %r12, %rcx
    mov     S8(%rsp), %r8
    call    lantern_get_unslashed_participating_indices
    mov     S7(%rsp), %rcx
    mov     %rcx, (%r12)
    test    %rax, %rax
    jnz     99f
    mov     %rbx, %rdi
    mov     S8(%rsp), %rsi
    lea     \out, %rdx
    call    lantern_get_total_balance
.endm
.else
/* The attesting balance of the attestations of getter at the epoch (a memory operand) into out (a memory operand): lantern_get_attesting_balance. */
.macro TOTALS_PENDING getter, epoch, out
    mov     %rbx, %rdi
    lea     \epoch, %rsi
    mov     S8(%rsp), %rdx
    call    \getter
    test    %rax, %rax
    jnz     99f
    mov     S9(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi
    mov     S8(%rsp), %rsi
    mov     %r12, %rdx
    lea     \out, %rcx
    call    lantern_get_attesting_balance
    test    %rax, %rax
    jnz     99f
.endm
.endif

/*
 * (state, config, mode, scratch, out) -> rax: the totals of the attestation rewards of the
 * previous epoch (node.md, lantern_node_reward_totals). rbx state, rbp config, r12 scratch, r13
 * out, r14 mode, r15 the validator count; S7 the scratch's size, S8 a list of indices (phase0: the
 * matching attestations), S9 (phase0) the scratch's size before them. Locals: L the current
 * epoch, L+8 a flag, L+16 the current epoch's target balance.
 */
SPEC_FUNCTION node_reward_totals
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r14
    mov     %rcx, %r12
    mov     %r8, %r13
.if FORK == FORK_PHASE0
    NEED_SCRATCH_B %r12, %rbx, 6, PENDING_REFS_BYTES, 9f
.else
    NEED_SCRATCH %r12, %rbx, 3, 9f
.endif
    mov     (%r12), %rax
    mov     %rax, S7(%rsp)
    mov     (BeaconState_validators + 8)(%rbx), %r15
    movq    $0, (L + 16)(%rsp)
    mov     %rbx, %rdi
    mov     %r13, %rsi
    call    lantern_get_previous_epoch
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     %r14, 64(%r13)
    mov     CONFIG_INACTIVITY_SCORE_BIAS(%rbp), %rax
    mov     %rax, 80(%r13)
    mov     CONFIG_INACTIVITY_SCORE_RECOVERY_RATE(%rbp), %rax
    mov     %rax, 88(%r13)
    MOVQ    %rax, MAX_EFFECTIVE_BALANCE     # the largest effective balance of the fork of the previous epoch
.if FORK >= FORK_ELECTRA
    MOVQ    %rax, MAX_EFFECTIVE_BALANCE_ELECTRA
.if FORK == FORK_ELECTRA
    mov     (BeaconState_fork + Fork_epoch)(%rbx), %rcx     # before the state's fork: deneb's
    cmp     %rcx, (%r13)
    jae     1f
    MOVQ    %rax, MAX_EFFECTIVE_BALANCE
1:
.endif
.endif
    mov     %rax, 72(%r13)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     24(%r13), %rdx
    call    lantern_get_total_active_balance
    test    %rax, %rax
    jnz     99f
.if FORK == FORK_PHASE0
    lea     24(%r13), %rdi
    lea     32(%r13), %rsi
    call    lantern_integer_squareroot
    TAKE_REFS %rax, %r12, %rcx
    mov     %rax, S8(%rsp)
    mov     %rcx, S9(%rsp)
    TOTALS_PENDING lantern_get_matching_source_attestations, (%r13), 40(%r13)
    TOTALS_PENDING lantern_get_matching_target_attestations, (%r13), 48(%r13)
    TOTALS_PENDING lantern_get_matching_head_attestations, (%r13), 56(%r13)
    test    %r14, %r14
    jz      5f
    cmpq    $(GENESIS_EPOCH + 1), L(%rsp)
    jbe     5f
    TOTALS_PENDING lantern_get_matching_target_attestations, L(%rsp), (L+16)(%rsp)
.else
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     32(%r13), %rdx
    call    lantern_get_base_reward_per_increment
    test    %rax, %rax
    jnz     99f
    mov     S7(%rsp), %rax
    SCRATCH_LIST %rcx, %r12, %rax, 0, %r15
    mov     %rcx, S8(%rsp)
    TOTALS_FLAG TIMELY_SOURCE_FLAG_INDEX, (%r13), 40(%r13)
    TOTALS_FLAG TIMELY_TARGET_FLAG_INDEX, (%r13), 48(%r13)
    TOTALS_FLAG TIMELY_HEAD_FLAG_INDEX, (%r13), 56(%r13)
    test    %r14, %r14
    jz      5f
    cmpq    $(GENESIS_EPOCH + 1), L(%rsp)
    jbe     5f
    TOTALS_FLAG TIMELY_TARGET_FLAG_INDEX, L(%rsp), (L+16)(%rsp)
.endif
5:  mov     (BeaconState_finalized_checkpoint + Checkpoint_epoch)(%rbx), %rdx
    test    %r14, %r14                      # mode 1: the finalized epoch weigh_justification_and_finalization would leave
    jz      6f
    mov     L(%rsp), %r8
    cmp     $(GENESIS_EPOCH + 1), %r8
    jbe     6f
    movzbl  BeaconState_justification_bits(%rbx), %ecx
    shl     $1, %ecx
    and     $0xf, %ecx
    mov     24(%r13), %rsi
    shl     $1, %rsi                        # total * 2
    imul    $3, 48(%r13), %rax
    cmp     %rsi, %rax
    jb      51f
    or      $2, %ecx
51: imul    $3, (L + 16)(%rsp), %rax
    cmp     %rsi, %rax
    jb      52f
    or      $1, %ecx
52: mov     (BeaconState_previous_justified_checkpoint + Checkpoint_epoch)(%rbx), %r9
    mov     (BeaconState_current_justified_checkpoint + Checkpoint_epoch)(%rbx), %r10
    mov     %ecx, %eax                      # the four rules in spec order: bits[1:4], bits[1:3], bits[0:3], bits[0:2]
    and     $0xe, %eax
    cmp     $0xe, %eax
    jne     53f
    lea     3(%r9), %rax
    cmp     %r8, %rax
    cmove   %r9, %rdx
53: mov     %ecx, %eax
    and     $0x6, %eax
    cmp     $0x6, %eax
    jne     54f
    lea     2(%r9), %rax
    cmp     %r8, %rax
    cmove   %r9, %rdx
54: mov     %ecx, %eax
    and     $0x7, %eax
    cmp     $0x7, %eax
    jne     55f
    lea     2(%r10), %rax
    cmp     %r8, %rax
    cmove   %r10, %rdx
55: mov     %ecx, %eax
    and     $0x3, %eax
    cmp     $0x3, %eax
    jne     6f
    lea     1(%r10), %rax
    cmp     %r8, %rax
    cmove   %r10, %rdx
6:  mov     (%r13), %rax                    # get_finality_delay, and the leak
    sub     %rdx, %rax
    mov     %rax, 8(%r13)
    xor     %ecx, %ecx
    cmp     $MIN_EPOCHS_TO_INACTIVITY_PENALTY, %rax
    seta    %cl
    mov     %rcx, 16(%r13)
    xor     %eax, %eax
99: mov     S7(%rsp), %rcx
    mov     %rcx, (%r12)
    LEAVE 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
SPEC_END node_reward_totals

.if FORK == FORK_PHASE0
/* The vote's item at ioff: base_reward in a leak, else base_reward * its attesting increments // the active increments. */
.macro IDEAL_VOTE boff, ioff
    mov     \boff(%rdi), %rax
    xor     %edx, %edx
    div     %r9
    imul    %rcx, %rax
    xor     %edx, %edx
    div     %r10
    test    %r11, %r11
    cmovnz  %rcx, %rax
    mov     %rax, \ioff(%r8)
.endm
.else
/* The flag's item at ioff: 0 in a leak, else base_reward * weight * its increments // (active_increments * WEIGHT_DENOMINATOR). */
.macro IDEAL_FLAG boff, weight, ioff
    mov     \boff(%rdi), %rax
    xor     %edx, %edx
    div     %r9
    imul    $\weight, %rcx, %rsi
    imul    %rsi, %rax
    xor     %edx, %edx
    div     %r10
    xor     %esi, %esi
    test    %r11, %r11
    cmovnz  %rsi, %rax
    mov     %rax, \ioff(%r8)
.endm
.endif

/*
 * (totals, effective_balance, out) -> rax: the item of a validator of the effective balance that
 * voted for all three in time (node.md, lantern_node_ideal_reward). A leaf: uses rcx, rdx, rsi, r8-r11.
 */
SPEC_FUNCTION node_ideal_reward
    UNWIND_END_PROLOGUE
    mov     %rdx, %r8
    mov     %rsi, 40(%r8)
    MOVQ    %r9, EFFECTIVE_BALANCE_INCREMENT
    mov     24(%rdi), %rax
    xor     %edx, %edx
    div     %r9
    mov     %rax, %r10                      # the active increments
    mov     16(%rdi), %r11                  # the leak
.if FORK == FORK_PHASE0
    imul    $BASE_REWARD_FACTOR, %rsi, %rax # get_base_reward
    xor     %edx, %edx
    divq    32(%rdi)
    shr     $2, %rax
    mov     %rax, %rcx
    mov     %rcx, %rsi
    shr     $3, %rsi                        # get_proposer_reward: // PROPOSER_REWARD_QUOTIENT
    IDEAL_VOTE 56, 0
    IDEAL_VOTE 48, 8
    IDEAL_VOTE 40, 16
    mov     %rcx, %rax                      # inclusion_delay at a delay of 1
    sub     %rsi, %rax
    mov     %rax, 24(%r8)
    lea     (,%rcx,4), %rax                 # inactivity in a leak: -(BASE_REWARDS_PER_EPOCH * base_reward - the proposer's)
    sub     %rsi, %rax
    neg     %rax
    xor     %edx, %edx
    test    %r11, %r11
    cmovz   %rdx, %rax
    mov     %rax, 32(%r8)
.else
    mov     %rsi, %rax                      # base_reward: increments * get_base_reward_per_increment
    xor     %edx, %edx
    div     %r9
    imul    32(%rdi), %rax
    mov     %rax, %rcx
    shl     $6, %r10
    IDEAL_FLAG 56, TIMELY_HEAD_WEIGHT, 0
    IDEAL_FLAG 48, TIMELY_TARGET_WEIGHT, 8
    IDEAL_FLAG 40, TIMELY_SOURCE_WEIGHT, 16
    movq    $0, 24(%r8)
    movq    $0, 32(%r8)
.endif
    xor     %eax, %eax
    ret
SPEC_END node_ideal_reward

.if FORK == FORK_PHASE0
/* Each validator of the window among the attesting indices of the attestations of getter: its status byte takes bit; with lowest 1, its delay byte the lowest inclusion_delay. */
.macro WINDOW_MARK getter, bit, lowest
    mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     S8(%rsp), %rdx
    call    \getter
    test    %rax, %rax
    jnz     99f
    mov     S8(%rsp), %rax
    mov     LIST_COUNT(%rax), %rcx
    add     $LIST_FIXED, %rax
    mov     %rax, (L + 16)(%rsp)
    mov     %rcx, (L + 24)(%rsp)
71: mov     (L + 16)(%rsp), %rax
    cmpq    $0, (L + 24)(%rsp)
    je      79f
    mov     (%rax), %rsi
    add     $8, %rax
    mov     %rax, (L + 16)(%rsp)
    decq    (L + 24)(%rsp)
    add     %rbx, %rsi
    mov     %rsi, (L + 32)(%rsp)
    mov     S10(%rsp), %rax
    mov     S9(%rsp), %rdx
    SCRATCH_GIVE %r15, %rax, 2, %rdx
    mov     %rbx, %rdi
    mov     (L + 32)(%rsp), %rsi
    mov     %rbp, %rdx
    mov     %r15, %rcx
    mov     S10(%rsp), %rax
    mov     S9(%rsp), %r9
    SCRATCH_LIST %r8, %r15, %rax, 1, %r9
    call    lantern_get_attesting_indices
    mov     S10(%rsp), %rcx
    mov     %rcx, (%r15)
    test    %rax, %rax
    jnz     99f
    mov     (L + 32)(%rsp), %rax
    mov     PendingAttestation_inclusion_delay(%rax), %r9
    mov     S10(%rsp), %rax
    mov     S9(%rsp), %rdx
    SCRATCH_LIST %rsi, %r15, %rax, 1, %rdx
    mov     LIST_COUNT(%rsi), %rcx
    add     $LIST_FIXED, %rsi
    mov     (L + 40)(%rsp), %rdi            # the status bytes
72: test    %rcx, %rcx
    jz      71b
    mov     (%rsi), %rax
    add     $8, %rsi
    dec     %rcx
    sub     %r13, %rax
    jb      72b
    cmp     %r14, %rax
    jae     72b
    orb     $\bit, (%rdi,%rax,2)
.if \lowest
    movzbl  1(%rdi,%rax,2), %edx
    cmp     %rdx, %r9
    jae     72b
    mov     %r9b, 1(%rdi,%rax,2)
.endif
    jmp     72b
79:
.endm

/* The vote's item at ioff: an attester, base_reward in a leak, else base_reward * its attesting increments // the active increments; another, -base_reward. */
.macro WINDOW_VOTE bit, boff, ioff
    test    $(1 << \bit), %cl
    jz      91f
    cmpq    $0, (L + 56)(%rsp)
    jne     92f
    mov     \boff(%r12), %rax
    xor     %edx, %edx
    MOVQ    %r10, EFFECTIVE_BALANCE_INCREMENT
    div     %r10
    imul    %rdi, %rax
    xor     %edx, %edx
    divq    (L + 48)(%rsp)
    mov     %rax, \ioff(%r8)
    jmp     93f
92: mov     %rdi, \ioff(%r8)
    jmp     93f
91: mov     %rdi, %rax
    neg     %rax
    mov     %rax, \ioff(%r8)
93:
.endm
.else
/* The flag's item at ioff: participating, 0 in a leak, else base_reward * weight * its increments // (active_increments * WEIGHT_DENOMINATOR); not, with penal, -(base_reward * weight // WEIGHT_DENOMINATOR). */
.macro REWARD_FLAG bit, weight, boff, ioff, penal
    test    $(1 << \bit), %cl
    jz      91f
    cmpq    $0, (L + 56)(%rsp)
    jne     92f
    mov     \boff(%r12), %rax
    xor     %edx, %edx
    MOVQ    %r10, EFFECTIVE_BALANCE_INCREMENT
    div     %r10
    imul    $\weight, %rdi, %r10
    imul    %r10, %rax
    xor     %edx, %edx
    divq    (L + 48)(%rsp)
    mov     %rax, \ioff(%r8)
    jmp     92f
91:
.if \penal
    imul    $\weight, %rdi, %rax
    shr     $6, %rax
    neg     %rax
    mov     %rax, \ioff(%r8)
.endif
92:
.endm
.endif

/*
 * (state, config, totals, first, count, scratch, out) -> rax: the attestation rewards of the
 * validators first to first + count - 1 (node.md, lantern_node_attestation_rewards). rbx state,
 * rbp the CommitteeCache, r12 totals, r13 first, r14 count, r15 scratch; S7 out, S8 the validators
 * (phase0: first the matching attestations), S9 the validator count, S10 the scratch's size.
 * Locals: L and L+8 the previous epoch's participation (from altair) and its count, L+16 and L+24
 * the inactivity scores and their count (phase0: a list's cursor and count), L+32 an attestation,
 * L+40 (phase0) a status and a delay byte for each validator of the window, L+48 the active
 * increments (from altair * WEIGHT_DENOMINATOR), L+56 the leak, L+64 the place in the window,
 * L+72 the effective balance.
 */
SPEC_FUNCTION node_attestation_rewards
    ENTER 80
    mov     %rdi, %rbx
    mov     CONFIG_COMMITTEE_CACHE(%rsi), %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r9, %r15
    mov     (80 + 96)(%rsp), %rax           # the seventh argument
    mov     %rax, S7(%rsp)
    mov     (BeaconState_validators + 8)(%rbx), %rax
    mov     %rax, S9(%rsp)
    mov     %r13, %rcx
    add     %r14, %rcx
    jc      96f
    cmp     %rax, %rcx
    ja      96f
    mov     (%r15), %rax
    mov     %rax, S10(%rsp)
.if FORK == FORK_PHASE0
    NEED_SCRATCH_B %r15, %rbx, 6, PENDING_REFS_BYTES, 97f
    TAKE_REFS %rax, %r15, %rcx              # S10: the scratch's size before the matching attestations
    mov     %rax, S8(%rsp)
    mov     %rcx, S10(%rsp)
    mov     S9(%rsp), %rdx
    SCRATCH_LIST %rdi, %r15, %rcx, 0, %rdx  # the window's bytes: no vote, no delay
    add     $LIST_FIXED, %rdi
    mov     %rdi, (L + 40)(%rsp)
    mov     %r14, %rcx
    mov     $0xff00, %eax
1:  test    %rcx, %rcx
    jz      2f
    mov     %ax, (%rdi)
    add     $2, %rdi
    dec     %rcx
    jmp     1b
2:  WINDOW_MARK lantern_get_matching_source_attestations, 1, 1
    WINDOW_MARK lantern_get_matching_target_attestations, 2, 0
    WINDOW_MARK lantern_get_matching_head_attestations, 4, 0
.else
    NEED_SCRATCH %r15, %rbx, 1, 97f
    PART    %rax, %rcx, %rbx, BeaconState_previous_epoch_participation
    mov     %rax, L(%rsp)
    mov     %rcx, (L + 8)(%rsp)
    PART    %rax, %rcx, %rbx, BeaconState_inactivity_scores
    mov     %rax, (L + 16)(%rsp)
    mov     %rcx, (L + 24)(%rsp)
.endif
    PART    %rax, %rcx, %rbx, BeaconState_validators
    mov     %rax, S8(%rsp)
    mov     24(%r12), %rax
    xor     %edx, %edx
    MOVQ    %rcx, EFFECTIVE_BALANCE_INCREMENT
    div     %rcx                            # the active increments
.if FORK >= FORK_ALTAIR
    shl     $6, %rax                        # * WEIGHT_DENOMINATOR
.endif
    mov     %rax, (L + 48)(%rsp)
    mov     16(%r12), %rax                  # the leak
    mov     %rax, (L + 56)(%rsp)
    movq    $0, (L + 64)(%rsp)
3:  mov     (L + 64)(%rsp), %rax
    cmp     %r14, %rax
    jae     8f
    lea     (%r13,%rax), %rsi               # the validator
    imul    $48, %rax, %r8
    add     S7(%rsp), %r8                   # the item: 0
    xor     %edx, %edx
    mov     %rdx, (%r8)
    mov     %rdx, 8(%r8)
    mov     %rdx, 16(%r8)
    mov     %rdx, 24(%r8)
    mov     %rdx, 32(%r8)
    mov     %rdx, 40(%r8)
    mov     %rsi, %r9
    shl     $7, %r9
    add     S8(%rsp), %r9
    mov     (%r12), %rdx                    # eligible: active in the previous epoch, or slashed and not yet withdrawable
    cmp     Validator_activation_epoch(%r9), %rdx
    jb      4f
    cmp     Validator_exit_epoch(%r9), %rdx
    jb      5f
4:  cmpb    $0, Validator_slashed(%r9)
    je      7f
    lea     1(%rdx), %rax
    cmp     Validator_withdrawable_epoch(%r9), %rax
    jae     7f
5:  movq    $1, 40(%r8)
    mov     Validator_effective_balance(%r9), %rax
    mov     %rax, (L + 72)(%rsp)
.if FORK == FORK_PHASE0
    imul    $BASE_REWARD_FACTOR, %rax, %rax # get_base_reward
    xor     %edx, %edx
    divq    32(%r12)
    shr     $2, %rax
    mov     %rax, %rdi
    mov     (L + 40)(%rsp), %r10
    mov     (L + 64)(%rsp), %rax
    movzbl  (%r10,%rax,2), %ecx             # the window's status: 1 source, 2 target, 4 head
    movzbl  1(%r10,%rax,2), %r11d           # the lowest delay
    cmpb    $0, Validator_slashed(%r9)      # unslashed attesters only
    je      55f
    xor     %ecx, %ecx
55: WINDOW_VOTE 0, 40, 16
    WINDOW_VOTE 1, 48, 8
    WINDOW_VOTE 2, 56, 0
    mov     %rdi, %r10
    shr     $3, %r10                        # get_proposer_reward
    test    $1, %cl
    jz      61f
    mov     %rdi, %rax                      # inclusion_delay: the attester's part, // its lowest delay
    sub     %r10, %rax
    xor     %edx, %edx
    div     %r11
    mov     %rax, 24(%r8)
61: cmpq    $0, (L + 56)(%rsp)              # inactivity, in a leak
    je      7f
    lea     (,%rdi,4), %r11
    sub     %r10, %r11
    test    $2, %cl
    jnz     62f
    mov     (L + 72)(%rsp), %rax            # not a target attester: effective_balance * finality_delay // INACTIVITY_PENALTY_QUOTIENT
    imul    8(%r12), %rax
    xor     %edx, %edx
    MOVQ    %r10, INACTIVITY_PENALTY_QUOTIENT
    div     %r10
    add     %rax, %r11
62: neg     %r11
    mov     %r11, 32(%r8)
.else
    xor     %edx, %edx                      # base_reward
    MOVQ    %rcx, EFFECTIVE_BALANCE_INCREMENT
    div     %rcx
    imul    32(%r12), %rax
    mov     %rax, %rdi
    xor     %ecx, %ecx                      # the flags, of an unslashed validator
    cmp     (L + 8)(%rsp), %rsi
    jae     51f
    mov     L(%rsp), %r10
    movzbl  (%r10,%rsi), %ecx
51: cmpb    $0, Validator_slashed(%r9)
    je      52f
    xor     %ecx, %ecx
52: REWARD_FLAG TIMELY_SOURCE_FLAG_INDEX, TIMELY_SOURCE_WEIGHT, 40, 16, 1
    REWARD_FLAG TIMELY_TARGET_FLAG_INDEX, TIMELY_TARGET_WEIGHT, 48, 8, 1
    REWARD_FLAG TIMELY_HEAD_FLAG_INDEX, TIMELY_HEAD_WEIGHT, 56, 0, 0
    test    $(1 << TIMELY_TARGET_FLAG_INDEX), %cl   # inactivity: not a timely target
    jnz     7f
    xor     %eax, %eax
    cmp     (L + 24)(%rsp), %rsi
    jae     56f
    mov     (L + 16)(%rsp), %r10
    mov     (%r10,%rsi,8), %rax
56: cmpq    $0, 64(%r12)                    # mode 1: its score as process_inactivity_updates leaves it
    je      57f
    add     80(%r12), %rax
    cmpq    $0, (L + 56)(%rsp)
    jne     57f
    mov     88(%r12), %r10
    cmp     %r10, %rax
    cmovb   %rax, %r10
    sub     %r10, %rax
57: imul    (L + 72)(%rsp), %rax
    mov     80(%r12), %r10
    MOVQ    %r11, FORK_INACTIVITY_PENALTY_QUOTIENT
    imul    %r11, %r10
    xor     %edx, %edx
    div     %r10
    neg     %rax
    mov     %rax, 32(%r8)
.endif
7:  incq    (L + 64)(%rsp)
    jmp     3b
8:  xor     %eax, %eax
99:
.if FORK == FORK_PHASE0
    MOVQ    %rcx, PENDING_REFS_BYTES        # the scratch's size on entry
    add     S10(%rsp), %rcx
    mov     %rcx, (%r15)
.else
    mov     S10(%rsp), %rcx
    mov     %rcx, (%r15)
.endif
    LEAVE 80
96: mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 80
97: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 80
SPEC_END node_attestation_rewards

/* rdi = the fork's TypeDescriptor of the NODE_JSON_* kind r10, or 0. Uses rdi. */
LOCAL_FUNCTION node_type_of_kind
    UNWIND_END_PROLOGUE
    ADDRESS %rdi, lantern_type_SignedBeaconBlock
    cmp     $NODE_JSON_BLOCK, %r10
    je      9f
    ADDRESS %rdi, lantern_type_BeaconState
    cmp     $NODE_JSON_STATE, %r10
    je      9f
    ADDRESS %rdi, lantern_type_SignedVoluntaryExit
    cmp     $NODE_JSON_EXIT, %r10
    je      9f
    ADDRESS %rdi, lantern_type_ProposerSlashing
    cmp     $NODE_JSON_PROPOSER_SLASHING, %r10
    je      9f
    ADDRESS %rdi, lantern_type_AttesterSlashing
    cmp     $NODE_JSON_ATTESTER_SLASHING, %r10
    je      9f
.if FORK >= FORK_CAPELLA
    ADDRESS %rdi, lantern_type_SignedBLSToExecutionChange
    cmp     $NODE_JSON_BLS_CHANGE, %r10
    je      9f
.endif
    ADDRESS %rdi, lantern_type_Attestation
    cmp     $NODE_JSON_ATTESTATION, %r10
    je      9f
    ADDRESS %rdi, lantern_type_Attestations
    cmp     $NODE_JSON_ATTESTATIONS, %r10
    je      9f
    ADDRESS %rdi, lantern_type_SignedAggregateAndProof
    cmp     $NODE_JSON_AGGREGATE_AND_PROOF, %r10
    je      9f
.if FORK >= FORK_ALTAIR
    ADDRESS %rdi, lantern_type_SyncCommitteeMessage
    cmp     $NODE_JSON_SYNC_COMMITTEE_MESSAGE, %r10
    je      9f
    ADDRESS %rdi, lantern_type_SyncCommitteeContribution
    cmp     $NODE_JSON_SYNC_CONTRIBUTION, %r10
    je      9f
    ADDRESS %rdi, lantern_type_SignedContributionAndProof
    cmp     $NODE_JSON_CONTRIBUTION_AND_PROOF, %r10
    je      9f
    ADDRESS %rdi, lantern_type_SyncCommitteeSubscription
    cmp     $NODE_JSON_SYNC_SUBSCRIPTION, %r10
    je      9f
    ADDRESS %rdi, lantern_type_LightClientBootstrap
    cmp     $NODE_JSON_LC_BOOTSTRAP, %r10
    je      9f
    ADDRESS %rdi, lantern_type_LightClientUpdate
    cmp     $NODE_JSON_LC_UPDATE, %r10
    je      9f
    ADDRESS %rdi, lantern_type_LightClientFinalityUpdate
    cmp     $NODE_JSON_LC_FINALITY_UPDATE, %r10
    je      9f
    ADDRESS %rdi, lantern_type_LightClientOptimisticUpdate
    cmp     $NODE_JSON_LC_OPTIMISTIC_UPDATE, %r10
    je      9f
.endif
    ADDRESS %rdi, lantern_type_BeaconCommitteeSubscription
    cmp     $NODE_JSON_COMMITTEE_SUBSCRIPTION, %r10
    je      9f
    ADDRESS %rdi, lantern_type_ProposerPreparation
    cmp     $NODE_JSON_PROPOSER_PREPARATION, %r10
    je      9f
    ADDRESS %rdi, lantern_type_BeaconBlock
    cmp     $NODE_JSON_BEACON_BLOCK, %r10
    je      9f
.if FORK >= FORK_DENEB
    ADDRESS %rdi, lantern_type_BlockContents
    cmp     $NODE_JSON_BLOCK_CONTENTS, %r10
    je      9f
.endif
.if FORK >= FORK_BELLATRIX
    ADDRESS %rdi, lantern_type_SignedBlindedBeaconBlock
.else
    ADDRESS %rdi, lantern_type_SignedBeaconBlock
.endif
    cmp     $NODE_JSON_BLINDED_BLOCK, %r10
    je      9f
.if FORK >= FORK_ELECTRA
    ADDRESS %rdi, lantern_type_SingleAttestation
    cmp     $NODE_JSON_SINGLE_ATTESTATION, %r10
    je      9f
.endif
.if FORK >= FORK_DENEB && FORK < FORK_FULU
    ADDRESS %rdi, lantern_type_BlobSidecar
    cmp     $NODE_JSON_BLOB_SIDECAR, %r10
    je      9f
.endif
.if FORK >= FORK_FULU
    ADDRESS %rdi, lantern_type_DataColumnSidecar
    cmp     $NODE_JSON_DATA_COLUMN_SIDECAR, %r10
    je      9f
.endif
    xor     %edi, %edi
9:  ret
END_FUNCTION node_type_of_kind

/* (kind, ssz, cursor, out): lantern_json_encode_ssz with the fork's type of the NODE_JSON_* kind. */
SPEC_FUNCTION node_json
    FRAME 0
    mov     %rdi, %r10
    call    node_type_of_kind
    test    %rdi, %rdi
    jz      8f
    CALL_GLOBAL lantern_json_encode_ssz
    UNFRAME 0
8:  mov     $LANTERN_INVALID_EVENT, %eax
    UNFRAME 0
SPEC_END node_json

/*
 * (kind, json, scratch, out, fault): lantern_json_decode with the fork's type of the NODE_JSON_*
 * kind (node.md, NODE_WORK_API_SUBMIT); LANTERN_INVALID_JSON for a kind of no type in the fork.
 */
SPEC_FUNCTION node_json_decode
    FRAME 0
    mov     %rdi, %r10
    call    node_type_of_kind
    test    %rdi, %rdi
    jz      8f
    CALL_GLOBAL lantern_json_decode
    UNFRAME 0
8:  mov     $LANTERN_INVALID_JSON, %eax
    UNFRAME 0
SPEC_END node_json_decode

/*
 * rax = the bytes of the SSZ default value of the type node rsi of the TypeDescriptor rdi, written
 * at rdx: zero bytes for a fixed size type, none for a list, the byte 1 for a bitlist, and for a
 * variable container or vector its fixed part with the offsets, then each variable part. rbx the
 * descriptor, rbp the node, r12 out, r13 a field or element, r14 their end, r15 the bytes, S7
 * the first field or an index, S8 a size or a place in the fixed part.
 */
LOCAL_FUNCTION node_ssz_default
    ENTER 0
    mov     %rdi, %rbx
    mov     %rdx, %r12
    imul    $SSZ_NODE_STRIDE, %rsi, %rbp
    add     SSZ_DESC_NODES_OFFSET(%rbx), %rbp
    add     %rbx, %rbp
    mov     SSZ_NODE_SSZ_SIZE(%rbp), %r15
    test    %r15, %r15
    jz      1f
    mov     %r12, %rdi                      # a fixed size type: zero bytes
    mov     %r15, %rsi
    call    lantern_zero
    jmp     9f
1:  mov     SSZ_NODE_KIND(%rbp), %rax
    cmp     $SSZ_KIND_BIT_LIST, %rax
    jne     2f
    movb    $1, (%r12)                      # a bitlist: its delimiter bit
    mov     $1, %r15d
    jmp     9f
2:  cmp     $SSZ_KIND_CONTAINER, %rax
    je      5f
    cmp     $SSZ_KIND_VECTOR, %rax
    je      3f
    xor     %r15d, %r15d                    # a list: empty
    jmp     9f
3:  mov     SSZ_NODE_LENGTH(%rbp), %r14     # a vector of variable elements: N offsets, then each element
    mov     SSZ_NODE_ELEMENT(%rbp), %r13
    lea     (,%r14,4), %r15
    movq    $0, S7(%rsp)
4:  mov     S7(%rsp), %rax
    cmp     %r14, %rax
    jae     9f
    mov     %r15d, (%r12,%rax,4)
    mov     %rbx, %rdi
    mov     %r13, %rsi
    lea     (%r12,%r15), %rdx
    call    node_ssz_default
    add     %rax, %r15
    incq    S7(%rsp)
    jmp     4b
5:  mov     SSZ_NODE_ELEMENT(%rbp), %r13    # a variable container: the fixed part
    mov     %r13, S7(%rsp)
    mov     SSZ_NODE_LENGTH(%rbp), %r14
    add     %r13, %r14
    xor     %r15d, %r15d
6:  cmp     %r14, %r13
    jae     7f
    mov     %r13, %rax
    shl     $5, %rax
    add     SSZ_DESC_FIELDS_OFFSET(%rbx), %rax
    add     %rbx, %rax
    mov     $4, %ecx                        # a variable field: its offset, written below
    testq   $SSZ_FIELD_VARIABLE, SSZ_FIELD_FLAGS(%rax)
    jnz     61f
    imul    $SSZ_NODE_STRIDE, SSZ_FIELD_NODE(%rax), %rcx
    add     SSZ_DESC_NODES_OFFSET(%rbx), %rcx
    mov     SSZ_NODE_SSZ_SIZE(%rbx,%rcx), %rcx
    mov     %rcx, S8(%rsp)
    lea     (%r12,%r15), %rdi
    mov     %rcx, %rsi
    call    lantern_zero
    mov     S8(%rsp), %rcx
61: add     %rcx, %r15
    inc     %r13
    jmp     6b
7:  mov     S7(%rsp), %r13                  # then each variable field, after its offset
    movq    $0, S8(%rsp)
71: cmp     %r14, %r13
    jae     9f
    mov     %r13, %rax
    shl     $5, %rax
    add     SSZ_DESC_FIELDS_OFFSET(%rbx), %rax
    add     %rbx, %rax
    testq   $SSZ_FIELD_VARIABLE, SSZ_FIELD_FLAGS(%rax)
    jnz     72f
    imul    $SSZ_NODE_STRIDE, SSZ_FIELD_NODE(%rax), %rcx
    add     SSZ_DESC_NODES_OFFSET(%rbx), %rcx
    mov     SSZ_NODE_SSZ_SIZE(%rbx,%rcx), %rcx
    add     %rcx, S8(%rsp)
    jmp     73f
72: mov     S8(%rsp), %rcx
    mov     %r15d, (%r12,%rcx)
    addq    $4, S8(%rsp)
    mov     %rbx, %rdi
    mov     SSZ_FIELD_NODE(%rax), %rsi
    lea     (%r12,%r15), %rdx
    call    node_ssz_default
    add     %rax, %r15
73: inc     %r13
    jmp     71b
9:  mov     %r15, %rax
    LEAVE 0
END_FUNCTION node_ssz_default

/*
 * (data, room, scratch, state, block): the anchor state and block of the genesis state in data.
 * rbx data, rbp room, r12 scratch, r13 state, r14 block, r15 the decoded state, then the block's
 * SSZ ByteList, S7 the default body's bytes, S8 the scratch size, restored on return. Locals: L
 * SizeBounds or a size, L+16 a root.
 */
SPEC_FUNCTION node_anchor
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     (%r12), %rax
    mov     %rax, S8(%rsp)
    ADDRESS %rdi, lantern_type_BeaconState  # the state, decoded at the end of scratch, then copied with room
    mov     %rbx, %rsi
    mov     %r12, %rdx
    call    node_decode
    cmp     $1, %rax
    je      8f
    ja      7f
    mov     %rdx, %r15
    mov     %r15, %rdi
    mov     %rbp, %rsi
    lea     L(%rsp), %rdx
    call    lantern_beacon_state_copy_size
    mov     L(%rsp), %rax
    cmp     %rax, (%r13)
    jb      8f
    mov     %r15, %rdi
    mov     %rbp, %rsi
    mov     %r13, %rdx
    call    lantern_beacon_state_copy
    test    %rax, %rax
    jnz     8f
    mov     S8(%rsp), %rax
    mov     %rax, (%r12)
    ADDRESS %rdi, lantern_type_BeaconBlockBody  # the default body's bytes: the least SSZ size of the type
    lea     L(%rsp), %rsi
    CALL_GLOBAL lantern_ssz_size_bounds
    mov     L(%rsp), %rax
    mov     %rax, S7(%rsp)
    lea     (24 + 84 + 7)(%rax), %rcx       # the block's SSZ bytes, a ByteList at the end of scratch
    and     $-8, %rcx
    lea     8(%rcx), %rdx
    mov     S8(%rsp), %rax
    cmp     %rdx, %rax
    jb      8f
    sub     %rcx, %rax
    mov     %rax, (%r12)
    lea     (%r12,%rax), %r15
    mov     %rcx, (%r15)
    movq    $24, 8(%r15)
    mov     S7(%rsp), %rax
    add     $84, %rax
    mov     %rax, 16(%r15)
    lea     BeaconState_latest_block_header(%r13), %rsi
    mov     BeaconBlockHeader_slot(%rsi), %rax
    mov     %rax, 24(%r15)
    mov     BeaconBlockHeader_proposer_index(%rsi), %rax
    mov     %rax, 32(%r15)
    lea     40(%r15), %rdi
    add     $BeaconBlockHeader_parent_root, %rsi
    mov     $32, %edx
    call    lantern_copy
    lea     (BeaconState_latest_block_header + BeaconBlockHeader_state_root)(%r13), %rsi
    mov     (%rsi), %rax                    # state_root: the header's, or hash_tree_root of the state
    or      8(%rsi), %rax
    or      16(%rsi), %rax
    or      24(%rsi), %rax
    jz      1f
    lea     72(%r15), %rdi
    mov     $32, %edx
    call    lantern_copy
    jmp     2f
1:  ADDRESS %rdi, lantern_type_BeaconState
    mov     %r13, %rsi
    mov     %r12, %rdx
    lea     72(%r15), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     8f
2:  movl    $84, (24 + 80)(%r15)            # the body's offset, then the default body
    ADDRESS %rdi, lantern_type_BeaconBlockBody
    mov     SSZ_DESC_ROOT(%rdi), %rsi
    lea     (24 + 84)(%r15), %rdx
    call    node_ssz_default
    ADDRESS %rdi, lantern_type_BeaconBlock
    mov     %r15, %rsi
    mov     %r12, %rdx
    mov     %r14, %rcx
    CALL_GLOBAL ssz_deserialize
    test    %rax, %rax
    jnz     8f
    PART    %rsi, %rax, %r14, BeaconBlock_body  # the default body must be the header's
    ADDRESS %rdi, lantern_type_BeaconBlockBody
    mov     %r12, %rdx
    lea     (L + 16)(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     8f
    lea     (BeaconState_latest_block_header + BeaconBlockHeader_body_root)(%r13), %rsi
    xor     %ecx, %ecx
3:  mov     (%rsi,%rcx), %rax
    cmp     (L + 16)(%rsp,%rcx), %rax
    jne     6f
    add     $8, %ecx
    cmp     $32, %ecx
    jb      3b
    xor     %eax, %eax
    jmp     99f
6:  mov     $LANTERN_INVALID_ANCHOR, %eax
    jmp     99f
7:  mov     $LANTERN_INVALID_ENCODING, %eax
    jmp     99f
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
99: mov     S8(%rsp), %rcx
    mov     %rcx, (%r12)
    LEAVE 48
SPEC_END node_anchor

/*
 * (data, room, scratch, state, block): the anchor of a start from the node's own history: data
 * holds two ByteLists, the second at the first multiple of 8 after the first: the SSZ bytes of a
 * BeaconState, then those of the message of its block, with the state's slot and root. state:
 * the state with room; block: the message. rbp room, r12 scratch, r13 state, r14 block, r15 the
 * decoded state, then the block's ByteList, S7 data's bytes, S8 the scratch size, restored on
 * return, S9 their count, S10 the block's place. Locals: L a size, L+16 a root.
 */
SPEC_FUNCTION node_anchor_block
    ENTER 48
    mov     8(%rdi), %rax
    add     %rdi, %rax
    mov     %rax, S7(%rsp)
    mov     16(%rdi), %rax
    mov     %rax, S9(%rsp)
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     (%r12), %rax
    mov     %rax, S8(%rsp)
    mov     S9(%rsp), %rdx                  # the state's ByteList: offset 24, size 24 + count, inside
    cmp     $24, %rdx
    jb      7f
    mov     S7(%rsp), %rsi
    cmpq    $24, 8(%rsi)
    jne     7f
    mov     16(%rsi), %rcx
    cmp     %rdx, %rcx
    ja      7f
    add     $24, %rcx
    cmp     %rcx, (%rsi)
    jne     7f
    cmp     %rdx, %rcx
    ja      7f
    add     $7, %rcx
    and     $-8, %rcx
    mov     %rcx, S10(%rsp)
    ADDRESS %rdi, lantern_type_BeaconState  # decoded, then copied with room
    mov     %r12, %rdx
    call    node_decode
    cmp     $1, %rax
    je      8f
    ja      7f
    mov     %rdx, %r15
    mov     %r15, %rdi
    mov     %rbp, %rsi
    lea     L(%rsp), %rdx
    call    lantern_beacon_state_copy_size
    mov     L(%rsp), %rax
    cmp     %rax, (%r13)
    jb      8f
    mov     %r15, %rdi
    mov     %rbp, %rsi
    mov     %r13, %rdx
    call    lantern_beacon_state_copy
    test    %rax, %rax
    jnz     8f
    mov     S8(%rsp), %rax
    mov     %rax, (%r12)
    mov     S10(%rsp), %rax                 # the block's ByteList, the same way
    lea     24(%rax), %rcx
    cmp     S9(%rsp), %rcx
    ja      7f
    mov     S7(%rsp), %r15
    add     %rax, %r15
    mov     S9(%rsp), %rdx
    sub     %rax, %rdx
    cmpq    $24, 8(%r15)
    jne     7f
    mov     16(%r15), %rcx
    cmp     %rdx, %rcx
    ja      7f
    add     $24, %rcx
    cmp     %rcx, (%r15)
    jne     7f
    cmp     %rdx, %rcx
    ja      7f
    ADDRESS %rdi, lantern_type_BeaconBlock
    mov     %r15, %rsi
    mov     %r12, %rdx
    mov     %r14, %rcx
    CALL_GLOBAL ssz_deserialize
    mov     S8(%rsp), %rcx
    mov     %rcx, (%r12)
    cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    je      8f
    test    %rax, %rax
    jnz     7f
    mov     BeaconBlock_slot(%r14), %rax    # its slot and state_root are the state's
    cmp     NODE_STATE_SLOT(%r13), %rax
    jne     6f
    ADDRESS %rdi, lantern_type_BeaconState
    mov     %r13, %rsi
    mov     %r12, %rdx
    lea     (L + 16)(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    mov     S8(%rsp), %rcx
    mov     %rcx, (%r12)
    test    %rax, %rax
    jnz     8f
    lea     BeaconBlock_state_root(%r14), %rdi
    lea     (L + 16)(%rsp), %rsi
    NE32    %rdi, %rsi, 6f
    xor     %eax, %eax
    jmp     99f
6:  mov     $LANTERN_INVALID_ANCHOR, %eax
    jmp     99f
7:  mov     $LANTERN_INVALID_ENCODING, %eax
    jmp     99f
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
99: mov     S8(%rsp), %rcx
    mov     %rcx, (%r12)
    LEAVE 48
SPEC_END node_anchor_block

/*
 * (state, scratch, out, size): size: the bytes of a ByteList of the state's SSZ bytes, 24 + their
 * count; out: that ByteList, when its size field holds at least size. rbx state, rbp scratch,
 * r12 out, r13 size, r14 the scratch size, restored on return.
 */
SPEC_FUNCTION node_state_bytes
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     (%rbp), %r14
    ADDRESS %rdi, lantern_type_BeaconState
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    mov     %r13, %rcx
    CALL_GLOBAL ssz_serialize_size
    mov     %r14, (%rbp)
    test    %rax, %rax
    jnz     8f
    mov     (%r13), %rax
    cmp     %rax, (%r12)
    jb      8f
    ADDRESS %rdi, lantern_type_BeaconState
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    mov     %r12, %rcx
    CALL_GLOBAL ssz_serialize
    mov     %r14, (%rbp)
    test    %rax, %rax
    jnz     8f
    xor     %eax, %eax
    LEAVE 0
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
SPEC_END node_state_bytes

/* (pre, room, config, scratch, out): upgrade_to_<fork> of the object's fork; phase0 has none. */
SPEC_FUNCTION node_upgrade
    ENTER 0
.if FORK == FORK_ALTAIR
    call    lantern_upgrade_to_altair
.elseif FORK == FORK_BELLATRIX
    call    lantern_upgrade_to_bellatrix
.elseif FORK == FORK_CAPELLA
    call    lantern_upgrade_to_capella
.elseif FORK == FORK_DENEB
    call    lantern_upgrade_to_deneb
.elseif FORK == FORK_ELECTRA
    call    lantern_upgrade_to_electra
.elseif FORK == FORK_FULU
    call    lantern_upgrade_to_fulu
.else
    mov     $LANTERN_INVALID_SLOT, %eax
.endif
    LEAVE 0
SPEC_END node_upgrade

/*
 * (data, state, config, scratch, result): the post-state again of a block the node imported:
 * state_transition of the SignedBeaconBlock in data with validate_result 0 and slots_done 1.
 * rbx data, rbp state, r12 config, r13 scratch, r14 result, S10 the scratch size. Locals: L
 * TransitionOptions.
 */
SPEC_FUNCTION node_replay
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     (%r13), %rax
    mov     %rax, S10(%rsp)
    movq    $0, (%r14)
    ADDRESS %rdi, lantern_type_SignedBeaconBlock
    mov     %rbx, %rsi
    mov     %r13, %rdx
    call    node_decode
    cmp     $1, %rax
    je      8f
    ja      9f
    movq    $0, L(%rsp)                     # validate_result 0, execution_valid 1, slots_done 1
    movq    $1, (L + 8)(%rsp)
    movq    $1, (L + 16)(%rsp)
    mov     %rbp, %rdi
    mov     %rdx, %rsi
    lea     L(%rsp), %rdx
    mov     %r12, %rcx
    mov     %r13, %r8
    mov     %r14, %r9
    call    lantern_state_transition
    jmp     99f
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    jmp     99f
9:  movq    $LANTERN_INVALID_ENCODING, (%r14)
    xor     %eax, %eax
99: mov     S10(%rsp), %rcx
    mov     %rcx, (%r13)
    LEAVE 32
SPEC_END node_replay

/*
 * (data, state, config, root, scratch, result): the proposer signature of the block in data, of
 * any fork, with the validators of state and the fork version of the block's epoch (node.md,
 * lantern_node_backfill). rbx data, rbp state, r12 config, r13 root, r14 scratch, r15 result, S8
 * the block's bytes, S9 the validator. Locals: L the epoch, L+8 the fork version, L+16 the domain
 * type, L+24 a ByteList header, L+48 the signing root, L+80 the root, L+112 the domain.
 */
SPEC_FUNCTION node_backfill
    ENTER 144
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r9, %r15
    cmpq    $(100 + 84), 16(%rbx)
    jb      7f
    mov     8(%rbx), %rax
    add     %rbx, %rax
    mov     %rax, S8(%rsp)
    mov     100(%rax), %rcx                 # the genesis block has no proposer
    test    %rcx, %rcx
    jz      5f
    mov     108(%rax), %rdx
    cmp     (BeaconState_validators + 8)(%rbp), %rdx
    jae     6f
    VALIDATOR %rax, %rbp, %rdx
    mov     %rax, S9(%rsp)
    shr     $LOG2_SLOTS_PER_EPOCH, %rcx
    mov     %rcx, L(%rsp)
    lea     L(%rsp), %rdi                   # compute_fork_version(the block's epoch)
    mov     %r12, %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_compute_fork_version
    movl    $DOMAIN_BEACON_PROPOSER, (L + 16)(%rsp)
    lea     (L + 16)(%rsp), %rdi
    lea     (L + 8)(%rsp), %rsi
    lea     BeaconState_genesis_validators_root(%rbp), %rdx
    mov     %r14, %rcx
    lea     (L + 112)(%rsp), %r8
    call    lantern_compute_domain
    test    %rax, %rax
    jnz     99f
    lea     (L + 80)(%rsp), %rax            # compute_signing_root: hash_tree_root(SigningData(root, domain))
    COPY32  %rax, %r13
    lea     (L + 80)(%rsp), %rdi
    mov     $64, %esi
    lea     (L + 48)(%rsp), %rdx
    call    sha256_short
    mov     S9(%rsp), %rdi
    add     $Validator_pubkey, %rdi
    mov     S8(%rsp), %rsi
    add     $4, %rsi
    lea     (L + 24)(%rsp), %rdx
    mov     %r14, %rcx
    call    verify_root_signature
    test    %rax, %rax
    jnz     99f
    test    %rdx, %rdx
    jz      8f
5:  movq    $0, (%r15)                      # LANTERN_VALID
    xor     %eax, %eax
    jmp     99f
6:  mov     $LANTERN_INVALID_PROPOSER_INDEX, %ecx
    jmp     9f
7:  mov     $LANTERN_INVALID_ENCODING, %ecx
    jmp     9f
8:  mov     $LANTERN_INVALID_BLOCK_SIGNATURE, %ecx
9:  mov     %rcx, (%r15)
    xor     %eax, %eax
99: LEAVE 144
SPEC_END node_backfill

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

/*
 * (state rdi, epoch rsi, out rdx) -> rax: get_randao_mix of the epoch (2^64 - 1: the state's
 * epoch) when the state holds it, from the state's epoch - EPOCHS_PER_HISTORICAL_VECTOR + 1 to its
 * epoch; else LANTERN_NO_STATE_ANSWER (node.md, lantern_node_randao).
 */
SPEC_FUNCTION node_randao
    FRAME 0
    mov     BeaconState_slot(%rdi), %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    cmp     $-1, %rsi
    cmove   %rax, %rsi
    cmp     %rax, %rsi
    ja      8f
    sub     %rsi, %rax
    cmp     $EPOCHS_PER_HISTORICAL_VECTOR, %rax
    jae     8f
    and     $(EPOCHS_PER_HISTORICAL_VECTOR - 1), %rsi
    shl     $5, %rsi
    lea     BeaconState_randao_mixes(%rdi,%rsi), %rsi
    mov     %rdx, %rdi
    mov     $32, %edx
    call    lantern_copy
    xor     %eax, %eax
    UNFRAME 0
8:  mov     $LANTERN_NO_STATE_ANSWER, %eax
    UNFRAME 0
SPEC_END node_randao

/*
 * (store, scratch, out) -> status: get_weight of each node of the store, in node order, a u64 a
 * node at out, as lantern_get_head computes them all at once (node.md, lantern_node_weights).
 * rbx store, rbp scratch, r12 out, r13 node count, r14 the flags at the end of scratch.
 */
SPEC_FUNCTION node_weights
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    NEED_BALANCES %rbx, 8f
    mov     (Store_blocks + 8)(%rbx), %r13
    mov     (%rbp), %rax
    lea     (,%r13,8), %rcx
    lea     LANTERN_SCRATCH_FIXED(%rcx), %rdx
    cmp     %rdx, %rax
    jb      9f
    sub     %rcx, %rax
    lea     (%rbp,%rax), %r14
    mov     %r14, %rdi
    mov     %rcx, %rsi
    call    lantern_zero
    mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     %r14, %rdx
    call    weights
    test    %rax, %rax
    jnz     7f
    xor     %ecx, %ecx                      # a sum past 2^64 - 1
1:  cmp     %r13, %rcx
    jae     7f
    testq   $F_OVERFLOW, (%r14,%rcx,8)
    lea     1(%rcx), %rcx
    jz      1b
    mov     $LANTERN_INVALID_OVERFLOW, %eax
7:  LEAVE 0
8:  mov     $LANTERN_NEED_JUSTIFIED_STATE, %eax
    LEAVE 0
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
SPEC_END node_weights
.if EPOCHS_PER_HISTORICAL_VECTOR & (EPOCHS_PER_HISTORICAL_VECTOR - 1)
.error "lantern_node_randao takes EPOCHS_PER_HISTORICAL_VECTOR as a power of two"
.endif

/*
 * (state rdi, epoch rsi, scratch rdx, out rcx) -> rax: the index of each member of the state's
 * sync committee of the epoch (2^64 - 1: the state's epoch), current_sync_committee for the
 * period of the state's epoch, next_sync_committee for the next, by find_pubkeys with its table at
 * the end of scratch (node.md, lantern_node_sync_committee). Before altair, or another period:
 * LANTERN_NO_STATE_ANSWER.
 */
SPEC_FUNCTION node_sync_committee
    FRAME 0
.if FORK >= FORK_ALTAIR
    mov     %rdx, %r8
    mov     BeaconState_slot(%rdi), %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    cmp     $-1, %rsi
    cmove   %rax, %rsi
    mov     $EPOCHS_PER_SYNC_COMMITTEE_PERIOD, %r9d
    xor     %edx, %edx
    div     %r9
    mov     %rax, %r10
    mov     %rsi, %rax
    xor     %edx, %edx
    div     %r9
    mov     $(BeaconState_current_sync_committee + SyncCommittee_pubkeys), %esi
    cmp     %r10, %rax
    je      1f
    inc     %r10
    cmp     %r10, %rax
    jne     8f
    mov     $(BeaconState_next_sync_committee + SyncCommittee_pubkeys), %esi
1:  mov     (%r8), %rax                     # the key table at the end of scratch
    sub     $(SYNC_TABLE_BYTES + 24), %rax
    jb      9f
    add     %rdi, %rsi
    mov     %rcx, %rdx
    lea     (%r8,%rax), %rcx
    call    find_pubkeys
    test    %rax, %rax
    jnz     7f
    UNFRAME 0
7:  mov     $LANTERN_INVALID_ENCODING, %eax
    UNFRAME 0
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    UNFRAME 0
8:
.endif
    mov     $LANTERN_NO_STATE_ANSWER, %eax
    UNFRAME 0
SPEC_END node_sync_committee

/* lantern_node_blinded_block: the end of the offsets in a body's fixed part, the last of them that of the last variable field */
.if FORK >= FORK_BELLATRIX
.if FORK >= FORK_ELECTRA
.set BLINDED_BODY_OFFSETS_END, BeaconBlockBody_execution_requests__ssz + 4
.elseif FORK >= FORK_DENEB
.set BLINDED_BODY_OFFSETS_END, BeaconBlockBody_blob_kzg_commitments__ssz + 4
.elseif FORK >= FORK_CAPELLA
.set BLINDED_BODY_OFFSETS_END, BeaconBlockBody_bls_to_execution_changes__ssz + 4
.else
.set BLINDED_BODY_OFFSETS_END, BeaconBlockBody_execution_payload__ssz + 4
.endif
.endif

/*
 * (block rdi, scratch rsi, out rdx) -> rax: the SSZ bytes of the SignedBlindedBeaconBlock of the
 * SignedBeaconBlock in the ByteList block, in the ByteList out (node.md,
 * lantern_node_blinded_block); before bellatrix the bytes of block. rbx the block's bytes, rbp
 * their count, r12 the body's place in them, r13 out, r14 scratch, r15 the payload's place.
 * Locals: L the scratch's size, L+8 the header's SSZ ByteList, L+16 block, L+24 the header's
 * bytes less the payload's, L+32 the payload's end, L+40 the header's value.
 */
SPEC_FUNCTION node_blinded_block
    ENTER 48
    mov     %rdi, (L + 16)(%rsp)
    mov     8(%rdi), %rbx
    add     %rdi, %rbx
    mov     16(%rdi), %rbp
    mov     %rdx, %r13
    mov     %rsi, %r14
    mov     (%r14), %rax
    mov     %rax, L(%rsp)
.if FORK < FORK_BELLATRIX
    lea     24(%rbp), %rax                  # before bellatrix: the block's bytes
    cmp     (%r13), %rax
    ja      8f
    movq    $24, 8(%r13)
    mov     %rbp, 16(%r13)
    lea     24(%r13), %rdi
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    call    lantern_copy
    jmp     7f
.else
    cmp     $100, %rbp                      # the message at the offset at byte 0, its body at the offset in it
    jb      91f
    mov     (%rbx), %eax
    lea     84(%rax), %rcx
    cmp     %rbp, %rcx
    ja      91f
    mov     BeaconBlock_body__ssz(%rbx,%rax), %ecx
    lea     (%rax,%rcx), %r12
    lea     BLINDED_BODY_OFFSETS_END(%r12), %rcx
    cmp     %rbp, %rcx
    ja      91f
    mov     BeaconBlockBody_execution_payload__ssz(%rbx,%r12), %eax  # the payload: from its offset to the next field's, else to the end
    lea     (%r12,%rax), %r15
.if FORK >= FORK_CAPELLA
    mov     BeaconBlockBody_bls_to_execution_changes__ssz(%rbx,%r12), %eax
    add     %r12, %rax
.else
    mov     %rbp, %rax
.endif
    mov     %rax, (L + 32)(%rsp)
    cmp     %rax, %r15
    ja      91f
    cmp     %rbp, %rax
    ja      91f
    ADDRESS %rdi, lantern_type_SignedBeaconBlock    # the decoded block's payload
    mov     (L + 16)(%rsp), %rsi
    mov     %r14, %rdx
    call    node_decode
    cmp     $1, %rax
    je      8f
    ja      91f
    PART    %rax, %rcx, %rdx, SignedBeaconBlock_message
    PART    %rsi, %rcx, %rax, BeaconBlock_body
    PART    %rax, %rcx, %rsi, BeaconBlockBody_execution_payload
    mov     (%r14), %rcx                    # its header, as process_execution_payload builds it
    TX_BYTES %rdx, %rax
    add     $(LANTERN_SCRATCH_FIXED + HEADER_ROOM + 24 + PAYLOAD_WLIST_BYTES + 1024), %rdx
    cmp     %rdx, %rcx
    jb      8f
    lea     -HEADER_ROOM(%r14,%rcx), %rdi
    mov     %rdi, (L + 40)(%rsp)
    mov     %rax, %rsi
    mov     %r14, %rdx
    call    build_payload_header
    test    %rax, %rax
    jnz     6f
    mov     (L + 40)(%rsp), %rax            # its SSZ bytes, in a ByteList of 1024 bytes below it
    sub     %r14, %rax
    sub     $1024, %rax
    lea     (%r14,%rax), %rcx
    movq    $1024, (%rcx)
    mov     %rcx, (L + 8)(%rsp)
    mov     %rax, (%r14)
    ADDRESS %rdi, lantern_type_ExecutionPayloadHeader
    mov     (L + 40)(%rsp), %rsi
    mov     %r14, %rdx
    CALL_GLOBAL ssz_serialize
    test    %rax, %rax
    jnz     6f
    mov     (L + 8)(%rsp), %rax             # out: the block's bytes to the payload, the header's, the block's after the payload
    mov     16(%rax), %rcx
    mov     (L + 32)(%rsp), %rdx
    sub     %r15, %rdx
    sub     %rdx, %rcx
    mov     %rcx, (L + 24)(%rsp)
    lea     (%rbp,%rcx), %rax
    lea     24(%rax), %rdx
    cmp     (%r13), %rdx
    ja      8f
    movq    $24, 8(%r13)
    mov     %rax, 16(%r13)
    lea     24(%r13), %rdi
    mov     %rbx, %rsi
    mov     %r15, %rdx
    call    lantern_copy
    mov     (L + 8)(%rsp), %rax
    lea     24(%r13,%r15), %rdi
    mov     8(%rax), %rsi
    add     %rax, %rsi
    mov     16(%rax), %rdx
    call    lantern_copy
    mov     (L + 8)(%rsp), %rax
    lea     24(%r13,%r15), %rdi
    add     16(%rax), %rdi
    mov     (L + 32)(%rsp), %rsi
    mov     %rbp, %rdx
    sub     %rsi, %rdx
    add     %rbx, %rsi
    call    lantern_copy
.if FORK >= FORK_CAPELLA
    mov     (L + 24)(%rsp), %rcx            # the offsets after the payload's grow by the header's bytes less the payload's
    lea     24(%r13,%r12), %rax
    add     %ecx, BeaconBlockBody_bls_to_execution_changes__ssz(%rax)
.if FORK >= FORK_DENEB
    add     %ecx, BeaconBlockBody_blob_kzg_commitments__ssz(%rax)
.endif
.if FORK >= FORK_ELECTRA
    add     %ecx, BeaconBlockBody_execution_requests__ssz(%rax)
.endif
.endif
.endif
7:  mov     L(%rsp), %rax
    mov     %rax, (%r14)
    xor     %eax, %eax
    LEAVE 48
6:  cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    je      8f
91: mov     L(%rsp), %rax
    mov     %rax, (%r14)
    mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 48
8:  mov     L(%rsp), %rax
    mov     %rax, (%r14)
    mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
SPEC_END node_blinded_block

/*
 * (state rdi, kind rsi, out rdx) -> rax: the address of the first item, the count and the bytes of
 * an item of the state's pending_deposits (kind 0), pending_partial_withdrawals (1) or
 * pending_consolidations (2); before electra LANTERN_NO_STATE_ANSWER (node.md, lantern_node_pending).
 */
SPEC_FUNCTION node_pending
    FRAME 0
.if FORK >= FORK_ELECTRA
    cmp     $1, %rsi
    je      1f
    ja      2f
    PART    %rax, %rcx, %rdi, BeaconState_pending_deposits
    mov     $PendingDeposit__mem, %esi
    jmp     5f
1:  PART    %rax, %rcx, %rdi, BeaconState_pending_partial_withdrawals
    mov     $PendingPartialWithdrawal__mem, %esi
    jmp     5f
2:  cmp     $2, %rsi
    jne     8f
    PART    %rax, %rcx, %rdi, BeaconState_pending_consolidations
    mov     $PendingConsolidation__mem, %esi
5:  mov     %rax, (%rdx)
    mov     %rcx, 8(%rdx)
    mov     %rsi, 16(%rdx)
    xor     %eax, %eax
    UNFRAME 0
8:
.endif
    mov     $LANTERN_NO_STATE_ANSWER, %eax
    UNFRAME 0
SPEC_END node_pending
.if FORK >= FORK_ELECTRA
.if PendingDeposit__mem != 192 || PendingPartialWithdrawal__mem != 24 || PendingConsolidation__mem != 16
.error "lantern_node_pending: an item is its SSZ encoding"
.endif
.endif

/*
 * (state rdi, out rsi) -> rax: the state's proposer_lookahead, (MIN_SEED_LOOKAHEAD + 1) *
 * SLOTS_PER_EPOCH u64; before fulu LANTERN_NO_STATE_ANSWER (node.md, lantern_node_proposer_lookahead).
 */
SPEC_FUNCTION node_proposer_lookahead
    FRAME 0
.if FORK >= FORK_FULU
    mov     %rsi, %rax
    lea     BeaconState_proposer_lookahead(%rdi), %rsi
    mov     %rax, %rdi
    mov     $(8 * API_LOOKAHEAD_SLOTS), %edx
    call    lantern_copy
    xor     %eax, %eax
.else
    mov     $LANTERN_NO_STATE_ANSWER, %eax
.endif
    UNFRAME 0
SPEC_END node_proposer_lookahead

/*
 * rax = a status: in the root r14 of lantern_node_gossip for the valid beacon_attestation rbp,
 * its data.slot, its committee index, its member and 0 (node.md): from electra, the member is the
 * place of attester_index in lantern_get_beacon_committee of the head state of the args rbx, +
 * 2^16 times the committee's length, the committee a list at the end of the scratch r12; before
 * electra, 0. r13 the list, r15 the scratch's size. Locals: L the slot, L+8 the index.
 */
LOCAL_FUNCTION node_gossip_member
    ENTER 16
.if FORK >= FORK_ELECTRA
    mov     (SingleAttestation_data + AttestationData_slot)(%rbp), %rax
    mov     SingleAttestation_committee_index(%rbp), %rcx
.else
    mov     (Attestation_data + AttestationData_slot)(%rbp), %rax
    mov     (Attestation_data + AttestationData_index)(%rbp), %rcx
.endif
    mov     %rax, (%r14)
    mov     %rcx, 8(%r14)
    movq    $0, 16(%r14)
    movq    $0, 24(%r14)
.if FORK >= FORK_ELECTRA
    mov     %rax, L(%rsp)
    mov     %rcx, (L + 8)(%rsp)
    mov     (%r12), %r15                    # the committee's list at the end of scratch
    mov     $(LIST_FIXED + 8 * MAX_VALIDATORS_PER_COMMITTEE), %edx
    mov     %r15, %rax
    sub     %rdx, %rax
    jb      8f
    mov     %rax, (%r12)
    lea     (%r12,%rax), %r13
    mov     %rdx, (%r13)
    movq    $LIST_FIXED, LIST_OFFSET(%r13)
    movq    $0, LIST_COUNT(%r13)
    mov     NodeGossip_head(%rbx), %rdi
    lea     L(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    mov     NodeGossip_config(%rbx), %rcx
    mov     CONFIG_COMMITTEE_CACHE(%rcx), %rcx
    mov     %r12, %r8
    mov     %r13, %r9
    call    lantern_get_beacon_committee
    mov     %r15, (%r12)
    test    %rax, %rax
    jnz     9f
    mov     LIST_OFFSET(%r13), %rdx         # the attester's place
    add     %r13, %rdx
    mov     LIST_COUNT(%r13), %rcx
    mov     SingleAttestation_attester_index(%rbp), %rsi
    xor     %eax, %eax
1:  cmp     %rcx, %rax
    jae     7f
    cmp     %rsi, (%rdx,%rax,8)
    je      2f
    inc     %rax
    jmp     1b
2:  shl     $16, %rcx
    or      %rcx, %rax
    mov     %rax, 16(%r14)
.endif
7:  xor     %eax, %eax
9:  LEAVE 16
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
END_FUNCTION node_gossip_member

/*
 * (args, data, scratch, result, root, index): the gossip validation of the topic args.topic for
 * the message in data, decoded with the fork's type. For beacon_block, blob_sidecar and
 * data_column_sidecar the proposer state first gets process_slots to the message's slot. A valid
 * beacon_block gives its root and blob count; a valid blob_sidecar the root of its block header
 * and its index. rbx args, rbp the message, r12 scratch, r13 result, r14 root, r15 the topic;
 * S7-S10 the arguments past the sixth. Locals: L a slot, L+8 a result, L+16 the proposer state,
 * L+24 the scratch size, restored on return, L+32 index.
 */
SPEC_FUNCTION node_gossip
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r9, (L + 32)(%rsp)
    movq    $0, (%r9)
    mov     (%r12), %rax
    mov     %rax, (L + 24)(%rsp)
    movq    $0, (%r13)
    mov     NodeGossip_topic(%rbx), %r15
    ADDRESS %rdi, lantern_type_SignedBeaconBlock    # the type of the topic
    cmp     $GOSSIP_BEACON_BLOCK, %r15
    je      1f
    ADDRESS %rdi, lantern_type_SignedAggregateAndProof
    cmp     $GOSSIP_BEACON_AGGREGATE_AND_PROOF, %r15
    je      1f
.if FORK >= FORK_ELECTRA
    ADDRESS %rdi, lantern_type_SingleAttestation
.else
    ADDRESS %rdi, lantern_type_Attestation
.endif
    cmp     $GOSSIP_BEACON_ATTESTATION, %r15
    je      1f
    ADDRESS %rdi, lantern_type_SignedVoluntaryExit
    cmp     $GOSSIP_VOLUNTARY_EXIT, %r15
    je      1f
    ADDRESS %rdi, lantern_type_ProposerSlashing
    cmp     $GOSSIP_PROPOSER_SLASHING, %r15
    je      1f
    ADDRESS %rdi, lantern_type_AttesterSlashing
    cmp     $GOSSIP_ATTESTER_SLASHING, %r15
    je      1f
.if FORK >= FORK_ALTAIR
    ADDRESS %rdi, lantern_type_SignedContributionAndProof
    cmp     $GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF, %r15
    je      1f
    ADDRESS %rdi, lantern_type_SyncCommitteeMessage
    cmp     $GOSSIP_SYNC_COMMITTEE, %r15
    je      1f
.endif
.if FORK >= FORK_CAPELLA
    ADDRESS %rdi, lantern_type_SignedBLSToExecutionChange
    cmp     $GOSSIP_BLS_TO_EXECUTION_CHANGE, %r15
    je      1f
.endif
.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    ADDRESS %rdi, lantern_type_BlobSidecar
    cmp     $GOSSIP_BLOB_SIDECAR, %r15
    je      1f
.endif
.if FORK >= FORK_FULU
    ADDRESS %rdi, lantern_type_DataColumnSidecar
    cmp     $GOSSIP_DATA_COLUMN_SIDECAR, %r15
    je      1f
.endif
    movq    $LANTERN_GOSSIP_IGNORE, (%r13)  # a topic of no type in this fork
    xor     %eax, %eax
    jmp     99f
1:  mov     %rbp, %rsi
    mov     %r12, %rdx
    call    node_decode
    cmp     $1, %rax
    je      8f
    ja      7f
    mov     %rdx, %rbp
    mov     NodeGossip_proposer(%rbx), %rax # the proposer state at the message's slot
    mov     %rax, (L + 16)(%rsp)
    test    %rax, %rax
    jz      20f
    cmp     $GOSSIP_BEACON_BLOCK, %r15
    jne     11f
    PART    %rcx, %rdx, %rbp, SignedBeaconBlock_message
    mov     BeaconBlock_slot(%rcx), %rax
    jmp     14f
11:
.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    cmp     $GOSSIP_BLOB_SIDECAR, %r15
    jne     12f
    mov     (BlobSidecar_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(%rbp), %rax
    jmp     14f
12:
.endif
.if FORK >= FORK_FULU
    cmp     $GOSSIP_DATA_COLUMN_SIDECAR, %r15
    jne     13f
    mov     (DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(%rbp), %rax
    jmp     14f
13:
.endif
    jmp     20f
14: mov     %rax, L(%rsp)
    mov     (L + 16)(%rsp), %rdi
    cmp     NODE_STATE_SLOT(%rdi), %rax
    jbe     20f
    lea     L(%rsp), %rsi
    mov     NodeGossip_config(%rbx), %rdx
    mov     %r12, %rcx
    lea     (L + 8)(%rsp), %r8
    call    lantern_process_slots
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8f
    test    %rax, %rax
    jnz     99f
    cmpq    $0, (L + 8)(%rsp)
    je      20f
    movq    $LANTERN_GOSSIP_IGNORE, (%r13)  # the slots do not run: no answer of the spec
    jmp     99f
20: mov     NodeGossip_seen(%rbx), %rdi     # the check of the topic
    mov     NodeGossip_store(%rbx), %rsi
    mov     %rbp, %rdx
    lea     NodeGossip_time_ms(%rbx), %rcx
    mov     NodeGossip_head(%rbx), %rax
    cmpq    $0, (L + 16)(%rsp)
    jne     21f
    mov     %rax, (L + 16)(%rsp)
21: cmp     $GOSSIP_BEACON_BLOCK, %r15
    jne     30f
    mov     %rax, %r8
    mov     (L + 16)(%rsp), %r9
.if FORK == FORK_BELLATRIX
    mov     NodeGossip_justified(%rbx), %r10
    test    %r10, %r10
    cmovz   %rax, %r10
    mov     %r10, S7(%rsp)
    mov     %r12, S8(%rsp)
    mov     %r13, S9(%rsp)
.else
    mov     %r12, S7(%rsp)
    mov     %r13, S8(%rsp)
.endif
    call    lantern_validate_beacon_block_gossip
    test    %rax, %rax
    jnz     98f
    cmpq    $0, (%r13)                      # a valid block: its root and blob count
    jne     99f
    PART    %rsi, %rax, %rbp, SignedBeaconBlock_message
.if FORK >= FORK_DENEB
    PART    %rcx, %rax, %rsi, BeaconBlock_body
    mov     (BeaconBlockBody_blob_kzg_commitments + 8)(%rcx), %rax
    mov     (L + 32)(%rsp), %rcx
    mov     %rax, (%rcx)
.endif
    ADDRESS %rdi, lantern_type_BeaconBlock
    mov     %r12, %rdx
    mov     %r14, %rcx
    CALL_GLOBAL ssz_hash_tree_root
    cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    je      8f
    jmp     99f
30: cmp     $GOSSIP_BEACON_AGGREGATE_AND_PROOF, %r15
    jne     31f
    mov     %rax, %r8
    mov     %r12, %r9
    mov     %r13, S7(%rsp)
    call    lantern_validate_beacon_aggregate_and_proof_gossip
    jmp     98f
31: cmp     $GOSSIP_BEACON_ATTESTATION, %r15
    jne     32f
    lea     NodeGossip_subnet(%rbx), %r8
    mov     %rax, %r9
    mov     %r12, S7(%rsp)
    mov     %r13, S8(%rsp)
    call    lantern_validate_beacon_attestation_gossip
    test    %rax, %rax
    jnz     98f
    cmpq    $0, (%r13)                      # a valid attestation: its slot, committee index and member
    jne     99f
    call    node_gossip_member
    jmp     98f
32: cmp     $GOSSIP_VOLUNTARY_EXIT, %r15
    jne     33f
    mov     %rax, %r8
    mov     %r12, %r9
    mov     %r13, S7(%rsp)
    call    lantern_validate_voluntary_exit_gossip
    jmp     98f
33: cmp     $GOSSIP_PROPOSER_SLASHING, %r15
    jne     34f
    mov     %rax, %rcx
    mov     %r12, %r8
    mov     %r13, %r9
    call    lantern_validate_proposer_slashing_gossip
    jmp     98f
34: cmp     $GOSSIP_ATTESTER_SLASHING, %r15
    jne     35f
    mov     %rax, %rcx
    mov     %r12, %r8
    mov     %r13, %r9
    call    lantern_validate_attester_slashing_gossip
    jmp     98f
35:
.if FORK >= FORK_ALTAIR
    cmp     $GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF, %r15
    jne     36f
    mov     %rax, %r8
    mov     %r12, %r9
    mov     %r13, S7(%rsp)
    call    lantern_validate_sync_committee_contribution_and_proof_gossip
    jmp     98f
36: cmp     $GOSSIP_SYNC_COMMITTEE, %r15
    jne     37f
    lea     NodeGossip_subnet(%rbx), %r8
    mov     %rax, %r9
    mov     %r12, S7(%rsp)
    mov     %r13, S8(%rsp)
    call    lantern_validate_sync_committee_message_gossip
    test    %rax, %rax
    jnz     98f
    cmpq    $0, (%r13)                      # a valid message: its slot and its subnet's bit
    jne     99f
    mov     SyncCommitteeMessage_slot(%rbp), %rdx
    mov     %rdx, (%r14)
    mov     NodeGossip_subnet(%rbx), %rcx
    mov     $1, %edx
    shl     %cl, %rdx
    mov     %rdx, 8(%r14)
    movq    $0, 16(%r14)
    movq    $0, 24(%r14)
    jmp     99f
37:
.endif
.if FORK >= FORK_CAPELLA
    cmp     $GOSSIP_BLS_TO_EXECUTION_CHANGE, %r15
    jne     38f
    mov     %rax, %r8
    mov     %r12, %r9
    mov     %r13, S7(%rsp)
    call    lantern_validate_bls_to_execution_change_gossip
    jmp     98f
38:
.endif
.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    cmp     $GOSSIP_BLOB_SIDECAR, %r15
    jne     39f
    lea     NodeGossip_subnet(%rbx), %r8
    mov     %rax, %r9
    mov     (L + 16)(%rsp), %rax
    mov     %rax, S7(%rsp)
    mov     NodeGossip_settings(%rbx), %rax
    mov     %rax, S8(%rsp)
    mov     %r12, S9(%rsp)
    mov     %r13, S10(%rsp)
    call    lantern_validate_blob_sidecar_gossip
    test    %rax, %rax
    jnz     98f
    cmpq    $0, (%r13)                      # a valid sidecar: the root of its block header, its index
    jne     99f
    mov     BlobSidecar_index(%rbp), %rax
    mov     (L + 32)(%rsp), %rcx
    mov     %rax, (%rcx)
    ADDRESS %rdi, lantern_type_BeaconBlockHeader
    lea     (BlobSidecar_signed_block_header + SignedBeaconBlockHeader_message)(%rbp), %rsi
    mov     %r12, %rdx
    mov     %r14, %rcx
    CALL_GLOBAL ssz_hash_tree_root
    cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    je      8f
    jmp     99f
39:
.endif
.if FORK >= FORK_FULU
    cmp     $GOSSIP_DATA_COLUMN_SIDECAR, %r15
    jne     40f
    lea     NodeGossip_subnet(%rbx), %r8
    mov     %rax, %r9
    mov     (L + 16)(%rsp), %rax
    mov     %rax, S7(%rsp)
    mov     NodeGossip_settings(%rbx), %rax
    mov     %rax, S8(%rsp)
    mov     %r12, S9(%rsp)
    mov     %r13, S10(%rsp)
    call    lantern_validate_data_column_sidecar_gossip
    test    %rax, %rax
    jnz     98f
    cmpq    $0, (%r13)                      # a valid sidecar: the root of its block header, its index
    jne     99f
    mov     DataColumnSidecar_index(%rbp), %rax
    mov     (L + 32)(%rsp), %rcx
    mov     %rax, (%rcx)
    ADDRESS %rdi, lantern_type_BeaconBlockHeader
    lea     (DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message)(%rbp), %rsi
    mov     %r12, %rdx
    mov     %r14, %rcx
    CALL_GLOBAL ssz_hash_tree_root
    cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    je      8f
    jmp     99f
40:
.endif
    movq    $LANTERN_GOSSIP_IGNORE, (%r13)
    xor     %eax, %eax
    jmp     99f
98: cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8f
    jmp     99f
7:  movq    $LANTERN_GOSSIP_REJECT, (%r13)  # no SSZ encoding of the type
    xor     %eax, %eax
    jmp     99f
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
99: mov     (L + 24)(%rsp), %rcx
    mov     %rcx, (%r12)
    LEAVE 48
SPEC_END node_gossip

.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
/*
 * (data, config, settings, scratch, result, root): the checks a reader of a blob sidecar response
 * makes: the index below the fork's limit, verify_blob_sidecar_inclusion_proof and
 * verify_blob_kzg_proof; then hash_tree_root of its block header. rbx config, rbp the sidecar,
 * r12 scratch, r13 result, r14 root, r15 settings. Locals: L an out, L+8 the scratch size,
 * restored on return.
 */
SPEC_FUNCTION node_blob_sidecar
    ENTER 16
    mov     %rdi, %rbp
    mov     %rsi, %rbx
    mov     %rdx, %r15
    mov     %rcx, %r12
    mov     %r8, %r13
    mov     %r9, %r14
    mov     (%r12), %rax
    mov     %rax, (L + 8)(%rsp)
    movq    $0, (%r13)
    ADDRESS %rdi, lantern_type_BlobSidecar
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    node_decode
    cmp     $1, %rax
    je      8f
    ja      9f
    mov     %rdx, %rbp
    mov     BlobSidecar_index(%rbp), %rax   # the index is below the blob limit
.if FORK == FORK_ELECTRA
    cmp     CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA(%rbx), %rax
.else
    cmp     CONFIG_MAX_BLOBS_PER_BLOCK(%rbx), %rax
.endif
    jae     6f
    mov     %rbp, %rdi                      # verify_blob_sidecar_inclusion_proof
    lea     L(%rsp), %rsi
    call    lantern_verify_blob_sidecar_inclusion_proof
    test    %rax, %rax
    jnz     99f
    cmpq    $0, L(%rsp)
    je      6f
    mov     %r15, %rdi                      # verify_blob_kzg_proof(blob, kzg_commitment, kzg_proof)
    lea     BlobSidecar_blob(%rbp), %rsi
    lea     BlobSidecar_kzg_commitment(%rbp), %rdx
    lea     BlobSidecar_kzg_proof(%rbp), %rcx
    mov     %r12, %r8
    lea     L(%rsp), %r9
    CALL_GLOBAL crypto_kzg_verify_blob_kzg_proof
    cmp     $CRYPTO_BUFFER_TOO_SMALL, %rax
    je      8f
    test    %rax, %rax
    jnz     6f                              # an input that does not decode
    cmpq    $0, L(%rsp)
    je      6f
    ADDRESS %rdi, lantern_type_BeaconBlockHeader
    lea     (BlobSidecar_signed_block_header + SignedBeaconBlockHeader_message)(%rbp), %rsi
    mov     %r12, %rdx
    mov     %r14, %rcx
    CALL_GLOBAL ssz_hash_tree_root
    cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    je      8f
    jmp     99f
6:  movq    $LANTERN_INVALID_BLOB_SIDECAR, (%r13)
    xor     %eax, %eax
    jmp     99f
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    jmp     99f
9:  movq    $LANTERN_INVALID_ENCODING, (%r13)
    xor     %eax, %eax
99: mov     (L + 8)(%rsp), %rcx
    mov     %rcx, (%r12)
    LEAVE 16
SPEC_END node_blob_sidecar
.endif

.if FORK >= FORK_FULU
/*
 * (data, config, settings, scratch, result, root): the checks a reader of a column sidecar
 * response makes: verify_data_column_sidecar, verify_data_column_sidecar_inclusion_proof and
 * verify_data_column_sidecar_kzg_proofs; then hash_tree_root of its block header. rbx config,
 * rbp the sidecar, r12 scratch, r13 result, r14 root, r15 settings. Locals: L an out, L+8 the
 * scratch size, restored on return.
 */
SPEC_FUNCTION node_column_sidecar
    ENTER 16
    mov     %rdi, %rbp
    mov     %rsi, %rbx
    mov     %rdx, %r15
    mov     %rcx, %r12
    mov     %r8, %r13
    mov     %r9, %r14
    mov     (%r12), %rax
    mov     %rax, (L + 8)(%rsp)
    movq    $0, (%r13)
    ADDRESS %rdi, lantern_type_DataColumnSidecar
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    node_decode
    cmp     $1, %rax
    je      8f
    ja      9f
    mov     %rdx, %rbp
    mov     %rbp, %rdi                      # verify_data_column_sidecar
    mov     %rbx, %rsi
    lea     L(%rsp), %rdx
    call    lantern_verify_data_column_sidecar
    test    %rax, %rax
    jnz     99f
    cmpq    $0, L(%rsp)
    je      6f
    mov     %rbp, %rdi                      # verify_data_column_sidecar_inclusion_proof
    mov     %r12, %rsi
    lea     L(%rsp), %rdx
    call    lantern_verify_data_column_sidecar_inclusion_proof
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8f
    test    %rax, %rax
    jnz     99f
    cmpq    $0, L(%rsp)
    je      6f
    mov     %rbp, %rdi                      # verify_data_column_sidecar_kzg_proofs
    mov     %r15, %rsi
    mov     %r12, %rdx
    lea     L(%rsp), %rcx
    call    lantern_verify_data_column_sidecar_kzg_proofs
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8f
    test    %rax, %rax
    jnz     99f
    cmpq    $0, L(%rsp)
    je      6f
    ADDRESS %rdi, lantern_type_BeaconBlockHeader
    lea     (DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message)(%rbp), %rsi
    mov     %r12, %rdx
    mov     %r14, %rcx
    CALL_GLOBAL ssz_hash_tree_root
    cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    je      8f
    jmp     99f
6:  movq    $LANTERN_INVALID_COLUMN_SIDECAR, (%r13)
    xor     %eax, %eax
    jmp     99f
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    jmp     99f
9:  movq    $LANTERN_INVALID_ENCODING, (%r13)
    xor     %eax, %eax
99: mov     (L + 8)(%rsp), %rcx
    mov     %rcx, (%r12)
    LEAVE 16
SPEC_END node_column_sidecar
.endif

.if FORK >= FORK_BELLATRIX
/*
 * (data, node, id, scratch, out, result): the HTTP request of engine_newPayload for the
 * SignedBeaconBlock in data: the JSON of lantern_engine_new_payload, the JWT of the node's secret
 * at time_ms / 1000, lantern_http_post to the node's engine_host. A payload whose block_hash and
 * parent_hash are zero gives LANTERN_NO_PAYLOAD. rbx node, rbp the block, r12 scratch, r13 out,
 * r14 result, r15 id, S7 the JSON, S8 the token, S9 the host, S10 the scratch size, restored on
 * return. Locals: L the time in seconds, L+8 the JSON's size.
 */
SPEC_FUNCTION node_new_payload
    ENTER 16
    mov     %rdi, %rbp
    mov     %rsi, %rbx
    mov     %rdx, %r15
    mov     %rcx, %r12
    mov     %r8, %r13
    mov     %r9, %r14
    mov     (%r12), %rax
    mov     %rax, S10(%rsp)
    movq    $0, (%r14)
    ADDRESS %rdi, lantern_type_SignedBeaconBlock
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    node_decode
    cmp     $1, %rax
    je      8f
    ja      9f
    PART    %rbp, %rax, %rdx, SignedBeaconBlock_message
    PART    %rcx, %rax, %rbp, BeaconBlock_body
    PART    %rsi, %rax, %rcx, BeaconBlockBody_execution_payload
    mov     ExecutionPayload_block_hash(%rsi), %rax     # no payload: zero block_hash and parent_hash
    or      (ExecutionPayload_block_hash + 8)(%rsi), %rax
    or      (ExecutionPayload_block_hash + 16)(%rsi), %rax
    or      (ExecutionPayload_block_hash + 24)(%rsi), %rax
    or      ExecutionPayload_parent_hash(%rsi), %rax
    or      (ExecutionPayload_parent_hash + 8)(%rsi), %rax
    or      (ExecutionPayload_parent_hash + 16)(%rsi), %rax
    or      (ExecutionPayload_parent_hash + 24)(%rsi), %rax
    jnz     1f
    movq    $LANTERN_NO_PAYLOAD, (%r14)
    xor     %eax, %eax
    jmp     99f
1:  mov     %rbp, %rdi                      # the JSON's room, then the three lists at the end of scratch
    lea     (L + 8)(%rsp), %rsi
    call    lantern_engine_new_payload_size
    test    %rax, %rax
    jnz     99f
    mov     (L + 8)(%rsp), %rcx
    add     $(24 + 7), %rcx
    and     $-8, %rcx
    lea     (280 + 88)(%rcx), %rdx
    mov     (%r12), %rax
    lea     4096(%rdx), %rsi
    cmp     %rsi, %rax
    jb      8f
    sub     %rdx, %rax
    mov     %rax, (%r12)
    lea     (%r12,%rax), %rdi
    mov     %rdi, S7(%rsp)
    mov     %rcx, (%rdi)
    movq    $24, 8(%rdi)
    movq    $0, 16(%rdi)
    add     %rcx, %rdi
    mov     %rdi, S8(%rsp)
    movq    $280, (%rdi)
    movq    $24, 8(%rdi)
    movq    $0, 16(%rdi)
    add     $280, %rdi
    mov     %rdi, S9(%rsp)
    movq    $88, (%rdi)
    movq    $24, 8(%rdi)
    mov     Node_engine_host_len(%rbx), %rdx
    mov     %rdx, 16(%rdi)
    add     $24, %rdi
    lea     Node_engine_host(%rbx), %rsi
    call    lantern_copy
    mov     %rbp, %rdi                      # the JSON
    mov     %r15, %rsi
    mov     %r12, %rdx
    mov     S7(%rsp), %rcx
    call    lantern_engine_new_payload
    test    %rax, %rax
    jnz     99f
    mov     Node_time_ms(%rbx), %rax        # the JWT
    xor     %edx, %edx
    mov     $1000, %ecx
    div     %rcx
    mov     %rax, L(%rsp)
    lea     Node_jwt_secret(%rbx), %rdi
    lea     L(%rsp), %rsi
    mov     %r12, %rdx
    mov     S8(%rsp), %rcx
    CALL_GLOBAL lantern_jwt_token
    test    %rax, %rax
    jnz     99f
    mov     S9(%rsp), %rdi                  # the HTTP request
    mov     S8(%rsp), %rsi
    mov     S7(%rsp), %rdx
    mov     %r13, %rcx
    CALL_GLOBAL lantern_http_post
    jmp     99f
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    jmp     99f
9:  movq    $LANTERN_INVALID_ENCODING, (%r14)
    xor     %eax, %eax
99: mov     S10(%rsp), %rcx
    mov     %rcx, (%r12)
    LEAVE 16
SPEC_END node_new_payload
.endif

/*
 * (state, request, scratch, out): node.md, lantern_node_produce_check. rbx state, rbp request, r12
 * scratch, r13 out, r14 the scratch size, r15 the proposer's Validator. Locals: L epoch, L+8 the
 * proposer, L+16 domain type, L+24 domain (32), L+56 the signing root after a ByteList header (56).
 */
SPEC_FUNCTION node_produce_check
    ENTER 112
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
.if FORK >= FORK_FULU
    NEED_SCRATCH %r12, %rbx, 0, 9f
.else
    NEED_SCRATCH %r12, %rbx, 2, 9f              # get_beacon_proposer_index takes S(2)
.endif
    mov     (%r12), %r14
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     %rbx, %rdi
.if FORK >= FORK_FULU
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_beacon_proposer_index
.else
    mov     %r12, %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_get_beacon_proposer_index
    mov     %r14, (%r12)
.endif
    test    %rax, %rax
    jnz     7f
    mov     (L + 8)(%rsp), %rax
    mov     %rax, (%r13)
    cmpq    $0, 128(%rbp)                   # skip_randao_verification: the point at infinity
    je      1f
    cmpb    $0xc0, (%rbp)
    jne     5f
    mov     $1, %ecx
2:  cmpb    $0, (%rbp,%rcx)
    jne     5f
    inc     %rcx
    cmp     $96, %rcx
    jb      2b
    jmp     3f
1:  mov     (L + 8)(%rsp), %rcx             # else the check of process_randao, no mix
    PART    %r15, %rdx, %rbx, BeaconState_validators
    mov     $LANTERN_INVALID_VALIDATOR_INDEX, %eax
    cmp     %rdx, %rcx
    jae     7f
    shl     $7, %rcx
    add     %rcx, %r15
    movl    $DOMAIN_RANDAO, (L + 16)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    lea     L(%rsp), %rdx
    mov     %r12, %rcx
    lea     (L + 24)(%rsp), %r8
    call    lantern_get_domain
    test    %rax, %rax
    jnz     7f
    ADDRESS %rdi, lantern_type_Uint64
    lea     L(%rsp), %rsi
    lea     (L + 24)(%rsp), %rdx
    mov     %r12, %rcx
    lea     (L + 80)(%rsp), %r8
    call    lantern_compute_signing_root
    test    %rax, %rax
    jnz     7f
    lea     Validator_pubkey(%r15), %rdi
    mov     %rbp, %rsi
    lea     (L + 56)(%rsp), %rdx
    mov     %r12, %rcx
    call    verify_root_signature
    test    %rax, %rax
    jnz     7f
    test    %rdx, %rdx
    jz      5f
3:
.if FORK < FORK_ELECTRA
    mov     (BeaconState_eth1_data + Eth1Data_deposit_count)(%rbx), %rcx    # deposits the block would need
    cmp     BeaconState_eth1_deposit_index(%rbx), %rcx
    ja      6f
.elseif FORK == FORK_ELECTRA
    mov     (BeaconState_eth1_data + Eth1Data_deposit_count)(%rbx), %rcx    # get_eth1_pending_deposit_count
    mov     BeaconState_deposit_requests_start_index(%rbx), %rdx
    cmp     %rdx, %rcx
    cmovae  %rdx, %rcx
    cmp     %rcx, BeaconState_eth1_deposit_index(%rbx)
    jb      6f
.endif
    xor     %eax, %eax
7:  LEAVE 112
5:  mov     $LANTERN_INVALID_RANDAO_REVEAL, %eax
    LEAVE 112
6:  mov     $LANTERN_INVALID_DEPOSITS, %eax
    LEAVE 112
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 112
SPEC_END node_produce_check

.if FORK >= FORK_BELLATRIX
/* (json, scratch, out, fault): node.md, lantern_node_payload_result. */
SPEC_FUNCTION node_payload_result
    FRAME 0
    mov     %rcx, %r8
    mov     %rdx, %rcx
    mov     %rsi, %rdx
    mov     %rdi, %rsi
.if FORK == FORK_BELLATRIX
    ADDRESS %rdi, lantern_type_ExecutionPayload
.else
    ADDRESS %rdi, lantern_type_GetPayloadResult
.endif
    CALL_GLOBAL lantern_engine_json_decode
    UNFRAME 0
SPEC_END node_payload_result
.endif

/*
 * (state, entry, draft, arg, scratch): node.md, lantern_node_produce_fold. rbx state, rbp the
 * entry's bytes, r12 their count, r13 the draft, r14 arg, r15 scratch; S7 the topic, S8 the entry's
 * fork, S9 an aggregate, S10 the place. Locals: L data, L+8 signature, L+16 length, L+24 the
 * committee index, L+40 the parent root (32).
 */
SPEC_FUNCTION node_produce_fold
    ENTER 96
    mov     %rdi, %rbx
    mov     8(%rsi), %rax
    mov     16(%rsi), %r12
    lea     (%rsi,%rax), %rbp
    mov     8(%rdx), %rax
    lea     (%rdx,%rax), %r13
    mov     %rcx, %r14
    mov     %r8, %r15
    movzbl  %r14b, %eax
    mov     %rax, S7(%rsp)
    mov     %r14, %rcx
    shr     $8, %rcx
    movzbl  %cl, %ecx
    mov     %rcx, S8(%rsp)
    cmp     $GOSSIP_BEACON_ATTESTATION, %rax
    je      100f
.if FORK >= FORK_ALTAIR
    cmp     $GOSSIP_SYNC_COMMITTEE, %rax
    je      200f
.endif
    mov     $MAX_VOLUNTARY_EXITS, %r9d      # an operation: a record, while its kind has room
    cmp     $GOSSIP_VOLUNTARY_EXIT, %rax
    je      1f
    mov     $MAX_PROPOSER_SLASHINGS, %r9d
    cmp     $GOSSIP_PROPOSER_SLASHING, %rax
    je      1f
.if FORK >= FORK_CAPELLA
    mov     $MAX_BLS_TO_EXECUTION_CHANGES, %r9d
    cmp     $GOSSIP_BLS_TO_EXECUTION_CHANGE, %rax
    je      1f
.endif
    cmp     $GOSSIP_ATTESTER_SLASHING, %rax
    jne     8f
    cmpq    $FORK_ELECTRA, S8(%rsp)         # an attester slashing of the fork's type
.if FORK >= FORK_ELECTRA
    jb      8f
    mov     $MAX_ATTESTER_SLASHINGS_ELECTRA, %r9d
.else
    jae     8f
    mov     $MAX_ATTESTER_SLASHINGS, %r9d
.endif
1:  mov     ProduceDraft_ops(%r13), %rcx
    lea     PRODUCE_DRAFT_OPS(%r13), %rdx
    lea     (%rdx,%rcx), %rsi               # the end of the records
    xor     %r8d, %r8d
2:  cmp     %rsi, %rdx                      # the records of the topic
    jae     3f
    mov     (%rdx), %rax
    cmp     S7(%rsp), %rax
    jne     21f
    inc     %r8
21: mov     8(%rdx), %rax
    add     $(16 + 7), %rax
    and     $-8, %rax
    add     %rax, %rdx
    jmp     2b
3:  cmp     %r9, %r8
    jae     8f
    cmpq    $GOSSIP_ATTESTER_SLASHING, S7(%rsp)  # the clashes, with the kinds folded before
    jne     4f
    mov     %rsi, %rcx
    lea     PRODUCE_DRAFT_OPS(%r13), %rdx
    mov     %rbp, %rdi
    mov     %r12, %rsi
    call    produce_takes_slashing
    test    %rax, %rax
    jz      8f
4:  cmpq    $GOSSIP_VOLUNTARY_EXIT, S7(%rsp)
    jne     5f
    mov     8(%rbp), %rdi
    lea     PRODUCE_DRAFT_OPS(%r13), %rsi
    mov     ProduceDraft_ops(%r13), %rdx
    add     %rsi, %rdx
    call    produce_slashed
    test    %rax, %rax
    jnz     8f
5:  mov     ProduceDraft_ops(%r13), %rcx
    lea     PRODUCE_DRAFT_OPS(%r13,%rcx), %rsi
    lea     (16 + 7)(%r12), %rax
    and     $-8, %rax
    add     %rcx, %rax
    MOVQ    %rdx, PRODUCE_DRAFT_OPS_ROOM
    cmp     %rdx, %rax
    ja      8f
    mov     S7(%rsp), %rdx
    mov     %rdx, (%rsi)
    mov     %r12, 8(%rsi)
    mov     %rax, ProduceDraft_ops(%r13)
    lea     16(%rsi), %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    lantern_copy
    xor     %eax, %eax
    LEAVE 96
8:  mov     $LANTERN_INVALID_ENCODING, %eax  # left out
    LEAVE 96
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 96

    /* An attestation of the fork's type: its data, signature, committee, length and place. */
100: cmpq   $FORK_ELECTRA, S8(%rsp)
.if FORK >= FORK_ELECTRA
    jb      8b
    cmp     $240, %r12                      # a SingleAttestation: committee_index 0, data at 16, signature at 144
    jne     8b
    lea     16(%rbp), %rax
    mov     %rax, L(%rsp)
    lea     144(%rbp), %rax
    mov     %rax, (L + 8)(%rsp)
    mov     (%rbp), %rax
    mov     %rax, (L + 24)(%rsp)
    mov     %r14, %rax                      # member: the place, + 2^16 x the length
    shr     $16, %rax
    movzwl  %ax, %ecx
    mov     %rcx, S10(%rsp)
    shr     $16, %rax
    mov     %rax, (L + 16)(%rsp)
    cmpq    $0, (16 + 8)(%rbp)              # data.index 0
    jne     8b
.else
    jae     8b
    cmp     $(228 + 1), %r12                # an Attestation: offset 228, data at 4, signature at 132, its bits
    jb      8b
    cmp     $(228 + MAX_VALIDATORS_PER_COMMITTEE / 8 + 1), %r12
    ja      8b
    cmpl    $228, (%rbp)
    jne     8b
    lea     4(%rbp), %rax
    mov     %rax, L(%rsp)
    lea     132(%rbp), %rax
    mov     %rax, (L + 8)(%rsp)
    mov     (4 + 8)(%rbp), %rax
    mov     %rax, (L + 24)(%rsp)
    lea     228(%rbp), %rsi
    lea     -229(%r12), %rdx                # the last byte: its highest bit is the length's
    movzbl  (%rsi,%rdx), %ecx
    test    %ecx, %ecx
    jz      8b
    bsr     %ecx, %ecx
    lea     (%rcx,%rdx,8), %r8
    mov     %r8, (L + 16)(%rsp)
    xor     %ecx, %ecx                      # the place: the first bit set
101: cmp    %r8, %rcx
    jae     8b
    bt      %rcx, (%rsi)
    jc      102f
    inc     %rcx
    jmp     101b
102: mov    %rcx, S10(%rsp)
.endif
    mov     (L + 16)(%rsp), %r8
    cmp     $MAX_VALIDATORS_PER_COMMITTEE, %r8
    ja      8b
    cmp     %r8, S10(%rsp)
    jae     8b
    mov     L(%rsp), %rsi                   # process_attestation's checks of slot, target and source
    mov     (%rsi), %r8                     # data.slot
    mov     88(%rsi), %r9                   # target.epoch
    mov     BeaconState_slot(%rbx), %rdi
    mov     %rdi, %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, %r10                      # the current epoch
    mov     %r8, %rax
    xor     %edx, %edx
    div     %rcx
    cmp     %r9, %rax
    jne     8b
    cmp     %r10, %r9
    je      103f
    test    %r10, %r10
    jz      8b
    lea     -1(%r10), %rax
    cmp     %rax, %r9
    jne     8b
103: lea    MIN_ATTESTATION_INCLUSION_DELAY(%r8), %rax
    cmp     %rdi, %rax
    ja      8b
.if FORK < FORK_DENEB
    lea     SLOTS_PER_EPOCH(%r8), %rax
    cmp     %rax, %rdi
    ja      8b
.endif
    lea     BeaconState_current_justified_checkpoint(%rbx), %rcx
    cmp     %r10, %r9
    je      104f
    lea     BeaconState_previous_justified_checkpoint(%rbx), %rcx
104: mov    48(%rsi), %rax                  # source: epoch, root
    cmp     (%rcx), %rax
    jne     8b
    lea     56(%rsi), %rdx
    lea     8(%rcx), %rax
    NE32    %rdx, %rax, 8b
    lea     PRODUCE_DRAFT_AGGREGATES(%r13), %rax  # its aggregate: of the same data and committee
    mov     %rax, S9(%rsp)
    xor     %ecx, %ecx
105: cmp    ProduceDraft_aggregates(%r13), %rcx
    jae     110f
    mov     S9(%rsp), %rdi
    mov     DraftAggregate_committee_index(%rdi), %rax
    cmp     (L + 24)(%rsp), %rax
    jne     107f
    mov     L(%rsp), %rsi
    xor     %edx, %edx
106: mov    (%rdi,%rdx), %rax
    cmp     (%rsi,%rdx), %rax
    jne     107f
    add     $8, %rdx
    cmp     $128, %rdx
    jb      106b
    jmp     120f
107: addq   $DraftAggregate__mem, S9(%rsp)
    inc     %rcx
    jmp     105b
110: mov    ProduceDraft_aggregates(%r13), %rax  # a new aggregate: its data, committee, length, order, signature
    cmp     $PRODUCE_DRAFT_AGGREGATE_COUNT, %rax
    jae     8b
    lea     1(%rax), %rcx
    mov     %rcx, ProduceDraft_aggregates(%r13)
    mov     S9(%rsp), %rdi
    mov     L(%rsp), %rsi
    mov     $128, %edx
    call    lantern_copy
    mov     S9(%rsp), %rdi
    mov     (L + 24)(%rsp), %rax
    mov     %rax, DraftAggregate_committee_index(%rdi)
    mov     (L + 16)(%rsp), %rax
    mov     %rax, DraftAggregate_length(%rdi)
    mov     ProduceDraft_aggregates(%r13), %rax
    dec     %rax
    mov     %rax, DraftAggregate_order(%rdi)
    add     $DraftAggregate_signature, %rdi
    mov     (L + 8)(%rsp), %rsi
    mov     $96, %edx
    call    lantern_copy
    jmp     130f
120: mov    S9(%rsp), %rdi                  # the same length, a place not taken, the signatures added
    mov     DraftAggregate_length(%rdi), %rax
    cmp     (L + 16)(%rsp), %rax
    jne     8b
    mov     S10(%rsp), %rcx
    bt      %rcx, DraftAggregate_bits(%rdi)
    jc      8b
    add     $DraftAggregate_signature, %rdi
    mov     (L + 8)(%rsp), %rsi
    mov     %r15, %rdx
    call    produce_add_signature
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      9b
    test    %rax, %rax
    jnz     8b
130: mov    S9(%rsp), %rdi                  # its place's bit
    mov     S10(%rsp), %rcx
    bts     %rcx, DraftAggregate_bits(%rdi)
    xor     %eax, %eax
    LEAVE 96

.if FORK >= FORK_ALTAIR
    /*
     * A SyncCommitteeMessage of the state's slot - 1 and the block's parent root: each place of its
     * validator's public key in the state's current_sync_committee not set yet, its signature added.
     */
200: cmp    $144, %r12
    jne     8b
    mov     (%rbp), %rax
    inc     %rax
    cmp     BeaconState_slot(%rbx), %rax
    jne     8b
    ADDRESS %rdi, lantern_type_BeaconBlockHeader  # the parent root: hash_tree_root(state.latest_block_header)
    lea     BeaconState_latest_block_header(%rbx), %rsi
    mov     %r15, %rdx
    lea     (L + 40)(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     9b
    lea     8(%rbp), %rax
    lea     (L + 40)(%rsp), %rcx
    NE32    %rax, %rcx, 8b
    mov     40(%rbp), %rcx                  # its validator's public key
    PART    %rdx, %rax, %rbx, BeaconState_validators
    cmp     %rax, %rcx
    jae     8b
    shl     $7, %rcx
    lea     Validator_pubkey(%rdx,%rcx), %rax
    mov     %rax, S9(%rsp)
    lea     (BeaconState_current_sync_committee + SyncCommittee_pubkeys)(%rbx), %rax
    mov     %rax, S8(%rsp)
    movq    $0, S10(%rsp)
201: mov    S10(%rsp), %rcx
    cmp     $SYNC_COMMITTEE_SIZE, %rcx
    jae     209f
    imul    $48, %rcx, %rsi
    add     S8(%rsp), %rsi
    mov     S9(%rsp), %rdi
    xor     %edx, %edx
202: mov    (%rsi,%rdx), %rax
    cmp     (%rdi,%rdx), %rax
    jne     208f
    add     $8, %rdx
    cmp     $48, %rdx
    jb      202b
    bt      %rcx, ProduceDraft_sync_bits(%r13)  # a place: set, the signature added
    jc      208f
    bts     %rcx, ProduceDraft_sync_bits(%r13)
    cmpq    $0, ProduceDraft_sync_set(%r13)
    jne     203f
    movq    $1, ProduceDraft_sync_set(%r13)
    lea     ProduceDraft_sync_signature(%r13), %rdi
    lea     48(%rbp), %rsi
    mov     $96, %edx
    call    lantern_copy
    jmp     208f
203: lea    ProduceDraft_sync_signature(%r13), %rdi
    lea     48(%rbp), %rsi
    mov     %r15, %rdx
    call    produce_add_signature
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      9b
208: incq   S10(%rsp)
    jmp     201b
209: xor    %eax, %eax
    LEAVE 96
.endif
SPEC_END node_produce_fold

/*
 * L1: the signature rsi added to the aggregate rdi with crypto_bls_aggregate, through a list of the
 * two at the end of scratch rdx: rax = LANTERN_OK, a status of crypto_bls_aggregate, or
 * LANTERN_BUFFER_TOO_SMALL. Locals: rsp+0 the aggregate, +8 the signature, +16 the list.
 */
LOCAL_FUNCTION produce_add_signature
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     (%rdx), %rax
    cmp     $(24 + 2 * 96 + 8), %rax
    jb      9f
    sub     $(24 + 2 * 96), %rax
    and     $-8, %rax
    add     %rdx, %rax
    mov     %rax, 16(%rsp)
    movq    $(24 + 2 * 96), (%rax)
    movq    $24, 8(%rax)
    movq    $2, 16(%rax)
    lea     24(%rax), %rdi
    mov     (%rsp), %rsi
    mov     $96, %edx
    call    lantern_copy
    mov     16(%rsp), %rdi
    add     $(24 + 96), %rdi
    mov     8(%rsp), %rsi
    mov     $96, %edx
    call    lantern_copy
    mov     16(%rsp), %rdi
    mov     (%rsp), %rsi
    CALL_GLOBAL crypto_bls_aggregate
    UNFRAME 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    UNFRAME 32
END_FUNCTION produce_add_signature

/* ---------------------------------------------------------------- produceBlockV3: the block */

.if Eth1Data_block_hash != 40 || Eth1Data__mem != 72
.error "node_produce_block copies Eth1Data as its 72 SSZ bytes"
.endif
.set PB_FIXED, 84                               /* BeaconBlock: slot, proposer_index, parent_root, state_root, the body's offset */
.set PB_SYNC, 220                               /* the body's offsets: proposer_slashings at 200 to voluntary_exits at 216 */
.if FORK >= FORK_ALTAIR
.set PB_PAYLOAD, PB_SYNC + SYNC_COMMITTEE_SIZE / 8 + 96
.else
.set PB_PAYLOAD, PB_SYNC
.endif
.if FORK >= FORK_BELLATRIX
.set PB_BLS, PB_PAYLOAD + 4
.else
.set PB_BLS, PB_PAYLOAD
.endif
.if FORK >= FORK_CAPELLA
.set PB_COMMITMENTS, PB_BLS + 4
.else
.set PB_COMMITMENTS, PB_BLS
.endif
.if FORK >= FORK_DENEB
.set PB_REQUESTS, PB_COMMITMENTS + 4
.else
.set PB_REQUESTS, PB_COMMITMENTS
.endif
.if FORK >= FORK_ELECTRA
.set PB_BODY_FIXED, PB_REQUESTS + 4
.set PB_MAX_ATTESTATIONS, MAX_ATTESTATIONS_ELECTRA
.else
.set PB_BODY_FIXED, PB_REQUESTS
.set PB_MAX_ATTESTATIONS, MAX_ATTESTATIONS
.endif

/* The offset of the body's field at pos: the write position r15 from the body S8. Uses rax, rcx. */
.macro PB_OFFSET pos
    mov     S8(%rsp), %rcx
    mov     %r15, %rax
    sub     %rcx, %rax
    mov     %eax, \pos(%rcx)
.endm

/*
 * (state, draft, params, scratch, out): node.md, lantern_node_produce_block. rbx state, rbp the
 * draft, r12 params, r13 scratch, r14 out, r15 the write position; S7 the block, S8 the body.
 * Locals: L proposer, L+8 the result's bytes, L+16 their count, L+24 the payload, L+32 its count,
 * L+40 the bundle, L+48 its count, L+56 balance before, L+64 1, L+72 a Result, L+80 the scratch
 * size, L+88 a ByteList view of the request lists (electra), L+256 24 bytes kept aside.
 */
SPEC_FUNCTION node_produce_block
    ENTER 288
    mov     %rdi, %rbx
    mov     8(%rsi), %rax
    lea     (%rsi,%rax), %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     (%r13), %rax
    mov     %rax, (L + 80)(%rsp)
    mov     (%r12), %rax                    # execution_valid 1, + 2 with skip_randao_verification
    mov     128(%rax), %rax
    lea     1(%rax,%rax), %rax
    mov     %rax, (L + 64)(%rsp)
    movq    $24, 8(%r14)                    # out: the block from offset 24, as large as its room
    movq    $0, 16(%r14)
    lea     24(%r14), %rax
    mov     %rax, S7(%rsp)
    mov     %rbx, %rdi                      # the proposer
.if FORK >= FORK_FULU
    lea     L(%rsp), %rsi
    call    lantern_get_beacon_proposer_index
.else
    mov     %r13, %rsi
    lea     L(%rsp), %rdx
    call    lantern_get_beacon_proposer_index
    mov     (L + 80)(%rsp), %rcx
    mov     %rcx, (%r13)
.endif
    test    %rax, %rax
    jnz     99f
    mov     L(%rsp), %rcx                   # its balance before
    PART    %rdx, %rax, %rbx, BeaconState_balances
    cmp     %rax, %rcx
    jae     97f
    mov     (%rdx,%rcx,8), %rax
    mov     %rax, (L + 56)(%rsp)
    xor     %eax, %eax                      # the engine's result: the payload, and from deneb the bundle
    mov     %rax, (L + 8)(%rsp)
    mov     %rax, (L + 16)(%rsp)
    mov     %rax, (L + 24)(%rsp)
    mov     %rax, (L + 32)(%rsp)
    mov     %rax, (L + 40)(%rsp)
    mov     %rax, (L + 48)(%rsp)
    mov     16(%r12), %rsi
    test    %rsi, %rsi
    jz      5f
    mov     8(%rsi), %rcx
    add     %rsi, %rcx
    mov     16(%rsi), %rdx
    mov     %rcx, (L + 8)(%rsp)
    mov     %rdx, (L + 16)(%rsp)
.if FORK == FORK_BELLATRIX
    mov     %rcx, (L + 24)(%rsp)            # the result is the payload
    mov     %rdx, (L + 32)(%rsp)
.else
    cmp     $(4 + 32), %rdx                 # GetPayloadResult: the payload's offset, block_value at 4
    jb      96f
    mov     (%rcx), %r8d
.if FORK >= FORK_DENEB
    mov     36(%rcx), %r9d                  # blobs_bundle's offset
.else
    mov     %rdx, %r9
.endif
    cmp     %r9, %r8
    ja      96f
    cmp     %rdx, %r9
    ja      96f
    lea     (%rcx,%r8), %rax
    mov     %rax, (L + 24)(%rsp)
    mov     %r9, %rax
    sub     %r8, %rax
    mov     %rax, (L + 32)(%rsp)
.if FORK >= FORK_DENEB
.if FORK >= FORK_ELECTRA
    mov     41(%rcx), %r10d                 # execution_requests' offset: the bundle up to it
.else
    mov     %rdx, %r10
.endif
    cmp     %r10, %r9
    ja      96f
    cmp     %rdx, %r10
    ja      96f
    lea     (%rcx,%r9), %rax
    mov     %rax, (L + 40)(%rsp)
    mov     %r10, %rax
    sub     %r9, %rax
    mov     %rax, (L + 48)(%rsp)
.endif
.endif
5:  mov     (%r14), %rax                    # room: the fixed parts of the block and the body
    cmp     $(PB_FIXED + PB_BODY_FIXED + 24), %rax
    jb      98f
    mov     S7(%rsp), %rdi
    mov     BeaconState_slot(%rbx), %rax
    mov     %rax, (%rdi)
    mov     L(%rsp), %rax
    mov     %rax, 8(%rdi)
    ADDRESS %rdi, lantern_type_BeaconBlockHeader  # parent_root: hash_tree_root(state.latest_block_header)
    lea     BeaconState_latest_block_header(%rbx), %rsi
    mov     %r13, %rdx
    mov     S7(%rsp), %rcx
    add     $16, %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     99f
    mov     S7(%rsp), %rdi
    xorps   %xmm0, %xmm0                    # state_root, written last
    movdqu  %xmm0, 48(%rdi)
    movdqu  %xmm0, 64(%rdi)
    movl    $PB_FIXED, 80(%rdi)
    lea     PB_FIXED(%rdi), %rax
    mov     %rax, S8(%rsp)
    mov     %rax, %rdi                      # randao_reveal, eth1_data (an empty eth1 chain's vote), graffiti
    mov     (%r12), %rsi
    mov     $96, %edx
    call    lantern_copy
    mov     S8(%rsp), %rdi
    add     $96, %rdi
    lea     BeaconState_eth1_data(%rbx), %rsi
    mov     $72, %edx
    call    lantern_copy
    mov     S8(%rsp), %rdi
    add     $168, %rdi
    mov     (%r12), %rsi
    add     $96, %rsi
    mov     $32, %edx
    call    lantern_copy
.if FORK >= FORK_ALTAIR
    mov     S8(%rsp), %rdi                  # the draft's sync aggregate; with none, no bit and the point at infinity
    add     $PB_SYNC, %rdi
    lea     ProduceDraft_sync_bits(%rbp), %rsi
    mov     $(SYNC_COMMITTEE_SIZE / 8 + 96), %edx
    call    lantern_copy
    cmpq    $0, ProduceDraft_sync_set(%rbp)
    jne     6f
    mov     S8(%rsp), %rdi
    add     $(PB_SYNC + SYNC_COMMITTEE_SIZE / 8), %rdi
    mov     $96, %esi
    call    lantern_zero
    mov     S8(%rsp), %rdi
    movb    $0xc0, (PB_SYNC + SYNC_COMMITTEE_SIZE / 8)(%rdi)
6:
.endif
    mov     S8(%rsp), %r15
    add     $PB_BODY_FIXED, %r15
    /* proposer_slashings, attester_slashings: the draft's records, which the folds kept free of clashes */
    PB_OFFSET 200
    mov     $GOSSIP_PROPOSER_SLASHING, %edi
    mov     %r15, %rsi
    call    produce_records
    mov     %rdx, %r15
    test    %rax, %rax
    jnz     98f
    PB_OFFSET 204
    mov     %r15, %rdi
    call    produce_attester_slashings
    mov     %rdx, %r15
    test    %rax, %rax
    jnz     98f
    /* attestations: the draft's aggregates */
    PB_OFFSET 208
    lea     L(%rsp), %rdi
    mov     %r15, %rsi
    call    produce_attestations
    mov     %rdx, %r15
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      98f
    test    %rax, %rax
    jnz     99f
    /* deposits: none; voluntary_exits */
    PB_OFFSET 212
    PB_OFFSET 216
    mov     $GOSSIP_VOLUNTARY_EXIT, %edi
    mov     %r15, %rsi
    call    produce_records
    mov     %rdx, %r15
    test    %rax, %rax
    jnz     98f
.if FORK >= FORK_BELLATRIX
    PB_OFFSET PB_PAYLOAD                    /* the payload, the empty one before the merge */
    cmpq    $0, (L + 24)(%rsp)
    jne     7f
.if FORK == FORK_BELLATRIX
    mov     %r15, %rdi                      # ExecutionPayload.empty(): the offsets of extra_data and transactions at 508
    mov     $508, %esi
    call    produce_room
    test    %rax, %rax
    jnz     98f
    mov     %r15, %rdi
    mov     $508, %esi
    call    lantern_zero
    movl    $508, 436(%r15)
    movl    $508, 504(%r15)
    add     $508, %r15
    jmp     71f
.else
    jmp     96f
.endif
7:  mov     %r15, %rdi
    mov     (L + 32)(%rsp), %rsi
    call    produce_room
    test    %rax, %rax
    jnz     98f
    mov     %r15, %rdi
    mov     (L + 24)(%rsp), %rsi
    mov     (L + 32)(%rsp), %rdx
    add     %rdx, %r15
    call    lantern_copy
71:
.endif
.if FORK >= FORK_CAPELLA
    PB_OFFSET PB_BLS
    mov     $GOSSIP_BLS_TO_EXECUTION_CHANGE, %edi
    mov     %r15, %rsi
    call    produce_records
    mov     %rdx, %r15
    test    %rax, %rax
    jnz     98f
.endif
.if FORK >= FORK_DENEB
    PB_OFFSET PB_COMMITMENTS                /* the bundle's commitments */
    mov     (L + 40)(%rsp), %rcx
    mov     (L + 48)(%rsp), %rdx
    cmp     $12, %rdx
    jb      96f
    mov     (%rcx), %r8d
    mov     4(%rcx), %r9d
    cmp     %r9, %r8
    ja      96f
    cmp     %rdx, %r9
    ja      96f
    lea     (%rcx,%r8), %rax
    mov     %rax, (L + 8)(%rsp)
    sub     %r8, %r9
    mov     %r9, (L + 16)(%rsp)
    mov     %r15, %rdi
    mov     %r9, %rsi
    call    produce_room
    test    %rax, %rax
    jnz     98f
    mov     %r15, %rdi
    mov     (L + 8)(%rsp), %rsi
    mov     (L + 16)(%rsp), %rdx
    add     %rdx, %r15
    call    lantern_copy
.endif
.if FORK >= FORK_ELECTRA
    PB_OFFSET PB_REQUESTS                   /* lantern_get_execution_requests of the result's request lists */
    mov     16(%r12), %rcx
    mov     8(%rcx), %rdx
    mov     16(%rcx), %r8
    add     %rcx, %rdx
    mov     41(%rdx), %r9d
    cmp     %r8, %r9
    ja      96f
    lea     (L + 112)(%rsp), %rsi           # a ByteList view of them in the locals
    lea     (%rdx,%r9), %rax
    sub     %rsi, %rax                      # its offset: from the view to the lists
    mov     %r8, %rcx
    sub     %r9, %rcx                       # their count
    mov     %rax, -16(%rsi)
    mov     %rcx, -8(%rsi)
    add     %rcx, %rax
    mov     %rax, -24(%rsi)
    mov     -24(%r15), %rax                 # the requests' room: the rest of out, as a ByteList at the write position less 24
    mov     %rax, (L + 256)(%rsp)
    mov     -16(%r15), %rax
    mov     %rax, (L + 264)(%rsp)
    mov     -8(%r15), %rax
    mov     %rax, (L + 272)(%rsp)
    mov     (%r14), %rax
    add     %r14, %rax
    sub     $24, %rax
    lea     -24(%r15), %rsi
    sub     %rsi, %rax
    mov     %rax, (%rsi)
    movq    $24, 8(%rsi)
    movq    $0, 16(%rsi)
    lea     (L + 88)(%rsp), %rdi
    call    lantern_get_execution_requests
    mov     -8(%r15), %rcx                  # the bytes written; the 24 bytes before them back
    mov     (L + 256)(%rsp), %rdx
    mov     %rdx, -24(%r15)
    mov     (L + 264)(%rsp), %rdx
    mov     %rdx, -16(%r15)
    mov     (L + 272)(%rsp), %rdx
    mov     %rdx, -8(%r15)
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      98f
    test    %rax, %rax
    jnz     96f
    add     %rcx, %r15
.endif
    mov     %r15, %rax                      # the block's bytes
    sub     S7(%rsp), %rax
    mov     %rax, 16(%r14)
    ADDRESS %rdi, lantern_type_BeaconBlock  # the state root: process_block of the decoded block, then the state's root
    mov     %r14, %rsi
    mov     %r13, %rdx
    call    node_decode
    cmp     $1, %rax
    je      98f
    ja      96f
    mov     %rbx, %rdi
    mov     %rdx, %rsi
    lea     (L + 64)(%rsp), %rdx
    mov     8(%r12), %rcx
    mov     %r13, %r8
    lea     (L + 72)(%rsp), %r9
    call    lantern_process_block
    mov     (L + 80)(%rsp), %rcx
    mov     %rcx, (%r13)
    test    %rax, %rax
    jnz     99f
    mov     (L + 72)(%rsp), %rax
    test    %rax, %rax
    jnz     99f
    mov     %rbx, %rdi
    xor     %esi, %esi
    mov     %r13, %rdx
    mov     S7(%rsp), %rcx
    add     $48, %rcx
    call    lantern_state_root
    test    %rax, %rax
    jnz     99f
    mov     L(%rsp), %rcx                   # consensus_block_value: the balance after less before, plus the proposer's withdrawals
    PART    %rdx, %rax, %rbx, BeaconState_balances
    mov     (%rdx,%rcx,8), %r8
    sub     (L + 56)(%rsp), %r8
.if FORK >= FORK_CAPELLA
    mov     (L + 24)(%rsp), %rsi            # the payload's withdrawals: from the offset at 508, 44 bytes each
    test    %rsi, %rsi
    jz      81f
    mov     (L + 32)(%rsp), %rdi
    mov     508(%rsi), %edx
    cmp     %rdi, %rdx
    ja      81f
80: lea     44(%rdx), %rax
    cmp     %rdi, %rax
    ja      81f
    cmp     %rcx, 8(%rsi,%rdx)
    jne     801f
    add     36(%rsi,%rdx), %r8
801: add    $44, %rdx
    jmp     80b
81:
.endif
    xor     %eax, %eax
    test    %r8, %r8
    cmovs   %rax, %r8
    mov     32(%r12), %rax
    mov     %r8, (%rax)
    mov     24(%r12), %rdi                  # execution_payload_value: the result's block_value, else 0
    xorps   %xmm0, %xmm0
    movdqu  %xmm0, (%rdi)
    movdqu  %xmm0, 16(%rdi)
.if FORK >= FORK_CAPELLA
    cmpq    $0, (L + 8)(%rsp)
    je      82f
    mov     16(%r12), %rsi
    mov     8(%rsi), %rax
    lea     4(%rsi,%rax), %rsi
    COPY32  %rdi, %rsi
82:
.endif
.if FORK >= FORK_DENEB
    lea     L(%rsp), %rdi                   # BlockContents: the block, the bundle's proofs and blobs
    call    produce_contents
    test    %rax, %rax
    jnz     98f
.endif
    xor     %eax, %eax
99: LEAVE 288
96: mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 288
97: mov     $LANTERN_INVALID_VALIDATOR_INDEX, %eax
    LEAVE 288
98: mov     (L + 80)(%rsp), %rcx
    mov     %rcx, (%r13)
    mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 288
SPEC_END node_produce_block

/* L0: rax = 0 when rsi bytes from rdi fit in the ByteList r14, else 1. Uses rcx. */
LOCAL_FUNCTION produce_room
    UNWIND_END_PROLOGUE
    mov     (%r14), %rcx
    add     %r14, %rcx
    lea     (%rdi,%rsi), %rax
    cmp     %rcx, %rax
    seta    %al
    movzbl  %al, %eax
    ret
END_FUNCTION produce_room

/*
 * L0: (index rdi, record rsi) -> rax = 1 when the index is in both attestations of the attester
 * slashing whose SSZ bytes follow the draft record rsi, else 0. Uses rcx, rdx, rsi, r8-r11.
 */
LOCAL_FUNCTION produce_in_slashing
    UNWIND_END_PROLOGUE
    mov     8(%rsi), %r8                    # its length
    add     $16, %rsi
    cmp     $8, %r8
    jb      9f
    mov     (%rsi), %ecx                    # the attestations: [o1, o2), then [o2, end)
    mov     4(%rsi), %r10d
    mov     %r10, %rdx
    xor     %r11d, %r11d
1:  cmp     %rdx, %rcx
    jae     9f
    mov     (%rsi,%rcx), %eax               # its indices, from its offset
    add     %rcx, %rax
2:  lea     8(%rax), %rcx
    cmp     %rdx, %rcx
    ja      9f
    cmp     %rdi, (%rsi,%rax)
    je      3f
    add     $8, %rax
    jmp     2b
3:  test    %r11, %r11                      # in the first: then the second
    jnz     4f
    mov     $1, %r11d
    mov     %r10, %rcx
    mov     %r8, %rdx
    jmp     1b
4:  mov     $1, %eax
    ret
9:  xor     %eax, %eax
    ret
END_FUNCTION produce_in_slashing

/*
 * L2: (topic rdi, write position rsi) -> rax = 0, or 1 for a short out; rdx = the write position.
 * The SSZ bytes of the draft's records of the topic in their order, back to back. rbx the topic,
 * r12 a record, r13 the records' end, r15 the position.
 */
LOCAL_FUNCTION produce_records
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %r15
    mov     ProduceDraft_ops(%rbp), %rax
    lea     PRODUCE_DRAFT_OPS(%rbp), %r12
    lea     (%r12,%rax), %r13
1:  cmp     %r13, %r12
    jae     8f
    cmp     %rbx, (%r12)
    jne     5f
    mov     %r15, %rdi
    mov     8(%r12), %rsi
    call    produce_room
    test    %rax, %rax
    jnz     9f
    mov     %r15, %rdi
    lea     16(%r12), %rsi
    mov     8(%r12), %rdx
    add     %rdx, %r15
    call    lantern_copy
5:  mov     8(%r12), %rax
    add     $(16 + 7), %rax
    and     $-8, %rax
    add     %rax, %r12
    jmp     1b
8:  xor     %eax, %eax
    mov     %r15, %rdx
    LEAVE 0
9:  mov     $1, %eax
    mov     %r15, %rdx
    LEAVE 0
END_FUNCTION produce_records

/*
 * L2: (write position rdi) -> rax = 0, or 1 for a short out; rdx = the write position. The draft's
 * attester slashing records as an SSZ list: their offsets, then their bytes. rbx the next offset,
 * r12 a record, r13 the end, r15 the position; S7 the next offset's place.
 */
LOCAL_FUNCTION produce_attester_slashings
    ENTER 0
    mov     %rdi, %r15
    mov     ProduceDraft_ops(%rbp), %rax
    lea     PRODUCE_DRAFT_OPS(%rbp), %r12
    lea     (%r12,%rax), %r13
    xor     %ebx, %ebx                      # their count
    mov     %r12, %rcx
1:  cmp     %r13, %rcx
    jae     2f
    cmpq    $GOSSIP_ATTESTER_SLASHING, (%rcx)
    jne     11f
    inc     %rbx
11: mov     8(%rcx), %rax
    add     $(16 + 7), %rax
    and     $-8, %rax
    add     %rax, %rcx
    jmp     1b
2:  shl     $2, %rbx                        # the offsets, the first slashing after them
    mov     %r15, %rdi
    mov     %rbx, %rsi
    call    produce_room
    test    %rax, %rax
    jnz     9f
    mov     %r15, S7(%rsp)
    add     %rbx, %r15
3:  cmp     %r13, %r12
    jae     8f
    cmpq    $GOSSIP_ATTESTER_SLASHING, (%r12)
    jne     4f
    mov     S7(%rsp), %rax
    mov     %ebx, (%rax)
    addq    $4, S7(%rsp)
    add     8(%r12), %rbx
    mov     %r15, %rdi
    mov     8(%r12), %rsi
    call    produce_room
    test    %rax, %rax
    jnz     9f
    mov     %r15, %rdi
    lea     16(%r12), %rsi
    mov     8(%r12), %rdx
    add     %rdx, %r15
    call    lantern_copy
4:  mov     8(%r12), %rax
    add     $(16 + 7), %rax
    and     $-8, %rax
    add     %rax, %r12
    jmp     3b
8:  xor     %eax, %eax
    mov     %r15, %rdx
    LEAVE 0
9:  mov     $1, %eax
    mov     %r15, %rdx
    LEAVE 0
END_FUNCTION produce_attester_slashings

/*
 * L1: (index rdi, records rsi, their end rdx) -> rax = 1 when a proposer slashing record of
 * [rsi, rdx) has the index as its proposer, or an attester slashing record has it in both
 * attestations; else 0. rbx the index, rbp a record, r12 the end.
 */
LOCAL_FUNCTION produce_slashed
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
1:  cmp     %r12, %rbp
    jae     8f
    mov     (%rbp), %rax
    cmp     $GOSSIP_PROPOSER_SLASHING, %rax
    jne     2f
    cmp     %rbx, (16 + 8)(%rbp)            # signed_header_1.message.proposer_index
    je      9f
    jmp     3f
2:  cmp     $GOSSIP_ATTESTER_SLASHING, %rax
    jne     3f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    produce_in_slashing
    test    %rax, %rax
    jnz     9f
3:  mov     8(%rbp), %rax
    add     $(16 + 7), %rax
    and     $-8, %rax
    add     %rax, %rbp
    jmp     1b
8:  xor     %eax, %eax
    LEAVE 0
9:  mov     $1, %eax
    LEAVE 0
END_FUNCTION produce_slashed

/*
 * L1: (the attester slashing's bytes rdi, their count rsi, records rdx, their end rcx) -> rax = 1
 * when an index is in both attestations (whose indices are sorted, as is_valid_indexed_attestation
 * holds them) and no proposer slashing record of [rdx, rcx) has it as its proposer; else 0. rbx
 * the bytes, rbp a place in the first list, r12 its end, r13 a place in the second, rsi its end,
 * r14 the records, r15 their end.
 */
LOCAL_FUNCTION produce_takes_slashing
    ENTER 0
    mov     %rdi, %rbx
    mov     %rdx, %r14
    mov     %rcx, %r15
    cmp     $8, %rsi
    jb      8f
    mov     (%rbx), %eax                    # the attestations: [o1, o2), [o2, count)
    mov     4(%rbx), %ecx
    cmp     %rcx, %rax
    ja      8f
    cmp     %rsi, %rcx
    ja      8f
    lea     228(%rax), %rdx
    cmp     %rcx, %rdx
    ja      8f
    lea     228(%rcx), %rdx
    cmp     %rsi, %rdx
    ja      8f
    mov     (%rbx,%rax), %edx               # each one's indices: from its offset to its end
    lea     (%rax,%rdx), %rbp
    mov     %rcx, %r12
    mov     (%rbx,%rcx), %edx
    lea     (%rcx,%rdx), %r13
1:  lea     8(%rbp), %rax
    cmp     %r12, %rax
    ja      8f
    lea     8(%r13), %rax
    cmp     %rsi, %rax
    ja      8f
    mov     (%rbx,%rbp), %rax
    mov     (%rbx,%r13), %rdx
    cmp     %rdx, %rax
    jb      2f
    ja      3f
    mov     %r14, %rcx                      # in both: a proposer slashing's proposer?
4:  cmp     %r15, %rcx
    jae     9f
    cmpq    $GOSSIP_PROPOSER_SLASHING, (%rcx)
    jne     5f
    cmp     %rax, (16 + 8)(%rcx)
    je      6f
5:  mov     8(%rcx), %rdx
    add     $(16 + 7), %rdx
    and     $-8, %rdx
    add     %rdx, %rcx
    jmp     4b
6:  add     $8, %r13
2:  add     $8, %rbp
    jmp     1b
3:  add     $8, %r13
    jmp     1b
8:  xor     %eax, %eax
    LEAVE 0
9:  mov     $1, %eax
    LEAVE 0
END_FUNCTION produce_takes_slashing

.set PB_COMMITTEE_BITS, (MAX_COMMITTEES_PER_SLOT + 7) / 8
/* An Attestation's fixed bytes: the bits' offset, data, signature, and from electra committee_bits */
.if FORK >= FORK_ELECTRA
.set PB_ATT_COMMITTEE, PB_COMMITTEE_BITS
.else
.set PB_ATT_COMMITTEE, 0
.endif
.set PB_ATT_FIXED, 228 + PB_ATT_COMMITTEE

/* L0: rax = 1 when the 128 bytes at rdi and rsi are equal, else 0. Uses rcx, rdx. */
LOCAL_FUNCTION produce_same_data
    UNWIND_END_PROLOGUE
    xor     %ecx, %ecx
1:  mov     (%rdi,%rcx), %rdx
    cmp     (%rsi,%rcx), %rdx
    jne     2f
    add     $8, %rcx
    cmp     $128, %rcx
    jb      1b
    mov     $1, %eax
    ret
2:  xor     %eax, %eax
    ret
END_FUNCTION produce_same_data

/*
 * L2: (the block's locals rdi, write position rsi) -> rax = 0, 1 for a short out or scratch, or a
 * status of crypto_bls_aggregate; rdx = the write position. The draft's aggregates chosen by
 * data.slot descending, then order, at most the fork's limit; before electra an Attestation of
 * each, from electra one Attestation for each data of the aggregates of every committee
 * (compute_on_chain_aggregate). The list: offsets, then the attestations. rbx the aggregates'
 * count, r12 the aggregates, r13 scratch, r15 the position; S7 the chosen indices (in scratch,
 * after a flag byte for each aggregate), S8 the chosen count, S9 the chosen aggregate, S10 an
 * aggregate. Locals: L the scratch size, L+8 an index, L+16 the bits' cursor, L+24 a committee.
 */
LOCAL_FUNCTION produce_attestations
    ENTER 32
    mov     %rsi, %r15
    mov     ProduceDraft_aggregates(%rbp), %rbx
    lea     PRODUCE_DRAFT_AGGREGATES(%rbp), %r12
    mov     (%r13), %rax                    # the flags and the chosen at the end of scratch
    mov     %rax, L(%rsp)
    lea     (8 * PB_MAX_ATTESTATIONS + 7)(%rbx), %rcx
    and     $-8, %rcx
    lea     1024(%rcx), %rdx
    cmp     %rdx, %rax
    jb      97f
    sub     %rcx, %rax
    mov     %rax, (%r13)
    lea     (%r13,%rax), %rdi
    mov     %rdi, S7(%rsp)
    mov     %rbx, %rsi
    call    lantern_zero
    mov     S7(%rsp), %rax                  # the chosen indices after the flags
    add     %rbx, %rax
    add     $7, %rax
    and     $-8, %rax
    mov     %rax, S7(%rsp)
    movq    $0, S8(%rsp)
1:  cmpq    $PB_MAX_ATTESTATIONS, S8(%rsp)  # the next: of the highest slot, then the lowest order
    jae     3f
    mov     $-1, %r8
    xor     %ecx, %ecx
    xor     %r9d, %r9d                      # the best's slot
    mov     (%r13), %rsi
    add     %r13, %rsi                      # the flags
2:  cmp     %rbx, %rcx
    jae     21f
    cmpb    $0, (%rsi,%rcx)
    jne     22f
    imul    $DraftAggregate__mem, %rcx, %rdx
    mov     (%r12,%rdx), %rax               # data.slot
    cmp     $-1, %r8
    je      23f
    cmp     %r9, %rax
    jbe     22f
23: mov     %rcx, %r8
    mov     %rax, %r9
22: inc     %rcx
    jmp     2b
21: cmp     $-1, %r8
    je      3f
    mov     S7(%rsp), %rax
    mov     S8(%rsp), %rcx
    mov     %r8, (%rax,%rcx,8)
    incq    S8(%rsp)
    movb    $1, (%rsi,%r8)                  # chosen: its flag, from electra those of its data too
.if FORK >= FORK_ELECTRA
    imul    $DraftAggregate__mem, %r8, %rdi
    add     %r12, %rdi
    mov     %rdi, (L + 8)(%rsp)
    xor     %ecx, %ecx
24: cmp     %rbx, %rcx
    jae     1b
    imul    $DraftAggregate__mem, %rcx, %rsi
    add     %r12, %rsi
    mov     (L + 8)(%rsp), %rdi
    mov     %rcx, (L + 16)(%rsp)
    call    produce_same_data
    mov     (L + 16)(%rsp), %rcx
    test    %rax, %rax
    jz      25f
    mov     (%r13), %rsi
    add     %r13, %rsi
    movb    $1, (%rsi,%rcx)
25: inc     %rcx
    jmp     24b
.else
    jmp     1b
.endif
3:  mov     S8(%rsp), %rax                  # the offsets: the size of each attestation
    shl     $2, %rax
    mov     %rax, (L + 24)(%rsp)
    mov     %r15, %rdi
    mov     %rax, %rsi
    call    produce_room
    test    %rax, %rax
    jnz     98f
    mov     (L + 24)(%rsp), %rax
    mov     %rax, (L + 16)(%rsp)            # the next offset
    movq    $0, (L + 8)(%rsp)
4:  mov     (L + 8)(%rsp), %rcx
    cmp     S8(%rsp), %rcx
    jae     5f
    mov     (L + 16)(%rsp), %rax
    mov     %eax, (%r15,%rcx,4)
    mov     S7(%rsp), %rax
    mov     (%rax,%rcx,8), %rdi
    call    produce_att_bits
    add     $(8 + 7), %rax                  # the bits: as many as the length, and the end bit
    shr     $3, %rax
    add     $PB_ATT_FIXED, %rax
    add     %rax, (L + 16)(%rsp)
    incq    (L + 8)(%rsp)
    jmp     4b
5:  add     (L + 24)(%rsp), %r15
    movq    $0, (L + 8)(%rsp)
6:  mov     (L + 8)(%rsp), %rcx             # each attestation
    cmp     S8(%rsp), %rcx
    jae     8f
    mov     S7(%rsp), %rax
    mov     (%rax,%rcx,8), %rdi
    imul    $DraftAggregate__mem, %rdi, %rax
    add     %r12, %rax
    mov     %rax, S9(%rsp)                  # the chosen aggregate
    call    produce_att_bits
    add     $(8 + 7), %rax
    shr     $3, %rax
    add     $PB_ATT_FIXED, %rax
    mov     %r15, %rdi
    mov     %rax, %rsi
    call    produce_room
    test    %rax, %rax
    jnz     98f
    movl    $PB_ATT_FIXED, (%r15)
    lea     4(%r15), %rdi                   # data
    mov     S9(%rsp), %rsi
    mov     $128, %edx
    call    lantern_copy
    lea     132(%r15), %rdi                 # signature: the first's
    mov     S9(%rsp), %rsi
    add     $DraftAggregate_signature, %rsi
    mov     $96, %edx
    call    lantern_copy
    mov     (L + 8)(%rsp), %rcx             # from electra the committee bits; the aggregation bits, zero
    mov     S7(%rsp), %rax
    mov     (%rax,%rcx,8), %rdi
    call    produce_att_bits
    lea     (8 + 7)(%rax), %rsi
    shr     $3, %rsi
    add     $PB_ATT_COMMITTEE, %rsi
    lea     228(%r15), %rdi
    call    lantern_zero
    movq    $0, (L + 16)(%rsp)              # the bits' cursor
.if FORK >= FORK_ELECTRA
    movq    $0, (L + 24)(%rsp)              # each committee in order: its aggregate of the data
61: cmpq    $MAX_COMMITTEES_PER_SLOT, (L + 24)(%rsp)
    jae     7f
    movq    $0, S10(%rsp)
62: mov     S10(%rsp), %r8
    cmp     %rbx, %r8
    jae     66f
    imul    $DraftAggregate__mem, %r8, %rsi
    add     %r12, %rsi
    mov     (L + 24)(%rsp), %rcx
    cmp     %rcx, DraftAggregate_committee_index(%rsi)
    jne     65f
    mov     S9(%rsp), %rdi
    call    produce_same_data
    test    %rax, %rax
    jz      65f
    mov     S10(%rsp), %r8
    imul    $DraftAggregate__mem, %r8, %rsi
    add     %r12, %rsi
    mov     (L + 24)(%rsp), %rcx            # its committee's bit
    bts     %rcx, 228(%r15)
    cmp     S9(%rsp), %rsi                  # its signature, after the first's
    je      63f
    mov     %rsi, S10(%rsp)
    lea     132(%r15), %rdi
    add     $DraftAggregate_signature, %rsi
    mov     %r13, %rdx
    call    produce_add_signature
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      97f
    test    %rax, %rax
    jnz     96f
    mov     S10(%rsp), %rsi
63: lea     (228 + PB_COMMITTEE_BITS)(%r15), %rdi  # its bits at the cursor
    mov     (L + 16)(%rsp), %rdx
    call    produce_copy_bits
    mov     %rax, (L + 16)(%rsp)
    jmp     66f
65: incq    S10(%rsp)
    jmp     62b
66: incq    (L + 24)(%rsp)
    jmp     61b
.else
    lea     228(%r15), %rdi
    mov     S9(%rsp), %rsi
    xor     %edx, %edx
    call    produce_copy_bits
    mov     %rax, (L + 16)(%rsp)
.endif
7:  mov     (L + 16)(%rsp), %rcx            # the end bit
    lea     PB_ATT_FIXED(%r15), %rdi
    bts     %rcx, (%rdi)
    shr     $3, %rcx
    lea     1(%rdi,%rcx), %r15
    incq    (L + 8)(%rsp)
    jmp     6b
8:  mov     L(%rsp), %rax
    mov     %rax, (%r13)
    xor     %eax, %eax
    mov     %r15, %rdx
    LEAVE 32
96: mov     L(%rsp), %rcx
    mov     %rcx, (%r13)
    mov     %r15, %rdx
    LEAVE 32
97: mov     L(%rsp), %rax
    mov     %rax, (%r13)
98: mov     $1, %eax
    mov     %r15, %rdx
    LEAVE 32
END_FUNCTION produce_attestations

/*
 * L0: (index rdi) -> rax: the aggregation bits of the attestation of the draft's aggregate rdi, r12
 * the aggregates, rbx their count: its length; from electra the lengths of the aggregates of its
 * data. Uses rcx, rdx, rsi, r8, r9.
 */
LOCAL_FUNCTION produce_att_bits
    UNWIND_END_PROLOGUE
    imul    $DraftAggregate__mem, %rdi, %rsi
    add     %r12, %rsi
.if FORK >= FORK_ELECTRA
    xor     %eax, %eax
    xor     %ecx, %ecx
1:  cmp     %rbx, %rcx
    jae     3f
    imul    $DraftAggregate__mem, %rcx, %r8
    add     %r12, %r8
    xor     %edx, %edx
2:  mov     (%rsi,%rdx), %r9
    cmp     (%r8,%rdx), %r9
    jne     4f
    add     $8, %rdx
    cmp     $128, %rdx
    jb      2b
    add     DraftAggregate_length(%r8), %rax
4:  inc     %rcx
    jmp     1b
3:  ret
.else
    mov     DraftAggregate_length(%rsi), %rax
    ret
.endif
END_FUNCTION produce_att_bits

/* L0: (bits rdi, aggregate rsi, cursor rdx) -> rax: the aggregate's length bits set at bit rdx of rdi on; the cursor after them. Uses rcx, r8. */
LOCAL_FUNCTION produce_copy_bits
    UNWIND_END_PROLOGUE
    mov     DraftAggregate_length(%rsi), %r8
    xor     %ecx, %ecx
1:  cmp     %r8, %rcx
    jae     2f
    bt      %rcx, DraftAggregate_bits(%rsi)
    jnc     3f
    lea     (%rdx,%rcx), %rax
    bts     %rax, (%rdi)
3:  inc     %rcx
    jmp     1b
2:  lea     (%rdx,%r8), %rax
    ret
END_FUNCTION produce_copy_bits

.if FORK >= FORK_DENEB
/*
 * L1: (the block's locals rdi) -> rax = 0, or 1 for a short out: out r14 holds the block from
 * offset 24; it becomes the BlockContents: the block moved 12 bytes on, the three offsets, the
 * bundle's proofs and blobs (the bundle at locals + 40, its bytes at + 48). Locals: rsp+0 the
 * bundle, +8 the blobs' offset, +16 the proofs' bytes, +24 the blobs' bytes.
 */
LOCAL_FUNCTION produce_contents
    FRAME 32
    mov     40(%rdi), %rsi                  # the bundle: its offsets of commitments, proofs, blobs
    mov     48(%rdi), %rdx
    cmp     $12, %rdx
    jb      9f
    mov     4(%rsi), %r8d
    mov     8(%rsi), %r9d
    cmp     %r9, %r8
    ja      9f
    cmp     %rdx, %r9
    ja      9f
    mov     %rsi, (%rsp)
    mov     %r9, 8(%rsp)
    mov     %r9, %r10                       # the proofs' bytes, then the blobs'
    sub     %r8, %r10
    mov     %r10, 16(%rsp)
    mov     %rdx, %r11
    sub     %r9, %r11
    mov     %r11, 24(%rsp)
    mov     16(%r14), %rcx                  # the block's
    lea     12(%rcx,%r10), %rax
    add     %r11, %rax
    mov     (%r14), %rdx
    sub     $24, %rdx
    cmp     %rdx, %rax
    ja      9f
    mov     %rax, 16(%r14)
    lea     24(%r14), %rdi                  # the block on by 12, from its end
    mov     %rcx, %rax
1:  test    %rax, %rax
    jz      2f
    dec     %rax
    movzbl  (%rdi,%rax), %edx
    mov     %dl, 12(%rdi,%rax)
    jmp     1b
2:  movl    $12, (%rdi)
    lea     12(%rcx), %rax
    mov     %eax, 4(%rdi)
    add     16(%rsp), %rax
    mov     %eax, 8(%rdi)
    lea     12(%rdi,%rcx), %rdi             # the proofs, then the blobs
    mov     (%rsp), %rsi
    add     %r8, %rsi
    mov     16(%rsp), %rdx
    call    lantern_copy
    mov     16(%r14), %rcx
    lea     24(%r14,%rcx), %rdi
    sub     24(%rsp), %rdi
    mov     (%rsp), %rsi
    add     8(%rsp), %rsi
    mov     24(%rsp), %rdx
    call    lantern_copy
    xor     %eax, %eax
    UNFRAME 32
9:  mov     $1, %eax
    UNFRAME 32
END_FUNCTION produce_contents
.endif

/* ---------------------------------------------------------------- publishBlockV2 */


/*
 * (body, json, scratch, out, facts): node.md, lantern_node_publish_decode. rbx body, rbp json,
 * r12 scratch, r13 out, r14 the type then the facts, r15 the value's bytes. Locals: L a JsonFault
 * (128), L+128 the facts, L+136 the scratch size.
 */
SPEC_FUNCTION node_publish_decode
    ENTER 144
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, (L + 128)(%rsp)
    mov     (%r12), %rax
    mov     %rax, (L + 136)(%rsp)
.if FORK >= FORK_DENEB
    ADDRESS %r14, lantern_type_SignedBlockContents
.else
    ADDRESS %r14, lantern_type_SignedBeaconBlock
.endif
    movq    $24, 8(%r13)
    movq    $0, 16(%r13)
    test    %rbp, %rbp
    jz      1f
    mov     %r14, %rdi                      # JSON: its SSZ bytes
    mov     %rbx, %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    lea     L(%rsp), %r8
    CALL_GLOBAL lantern_json_decode
    mov     (L + 136)(%rsp), %rcx
    mov     %rcx, (%r12)
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      9f
    test    %rax, %rax
    jnz     8f
    jmp     2f
1:  mov     8(%rbx), %rsi                   # SSZ: the bytes as they are
    mov     16(%rbx), %rdx
    lea     24(%rdx), %rax
    cmp     (%r13), %rax
    ja      9f
    mov     %rdx, 16(%r13)
    lea     24(%r13), %rdi
    add     %rbx, %rsi
    call    lantern_copy
2:  mov     %r14, %rdi                      # a value of the type
    mov     %r13, %rsi
    mov     %r12, %rdx
    call    node_decode
    mov     (L + 136)(%rsp), %rcx
    mov     %rcx, (%r12)
    cmp     $1, %rax
    je      9f
    test    %rax, %rax
    jnz     8f
    lea     24(%r13), %r15
    mov     (L + 128)(%rsp), %r14
.if FORK >= FORK_DENEB
    mov     (%r15), %esi                    # SignedBlockContents: the block [o0, o1), kzg_proofs [o1, o2), blobs [o2, n)
    mov     4(%r15), %edi
    mov     8(%r15), %r8d
    mov     (%r15,%rsi), %eax               # the block's message, its body: offsets checked by the decode
    add     %rsi, %rax
    mov     80(%r15,%rax), %ecx
    add     %rcx, %rax                      # the body's place
    mov     PB_COMMITMENTS(%r15,%rax), %ecx # blob_kzg_commitments: [c0, c1) of the body
.if FORK >= FORK_ELECTRA
    mov     PB_REQUESTS(%r15,%rax), %r9d
.else
    mov     %rdi, %r9
    sub     %rax, %r9
.endif
    sub     %rcx, %r9
    mov     %r9, %rax
    xor     %edx, %edx
    mov     $48, %ecx
    div     %rcx
    mov     %rax, %r9                       # the blob count
    mov     %r8, %rax                       # the proofs' count
    sub     %rdi, %rax
    xor     %edx, %edx
    div     %rcx
.if FORK >= FORK_FULU
    imul    $CELLS_PER_EXT_BLOB, %r9, %rcx
    cmp     %rcx, %rax
.else
    cmp     %r9, %rax
.endif
    jne     8f
    mov     16(%r13), %rax                  # the blobs' count
    sub     %r8, %rax
    xor     %edx, %edx
    mov     $PUB_BLOB_BYTES, %ecx
    div     %rcx
    cmp     %r9, %rax
    jne     8f
    mov     %r9, 8(%r14)
    mov     %rdi, %rdx                      # the signed block to the front
    sub     %rsi, %rdx
    mov     %rdx, 16(%r13)
    add     %r15, %rsi
    mov     %r15, %rdi
    call    lantern_copy
.else
    movq    $0, 8(%r14)
.endif
    mov     (%r15), %eax                    # facts: the slot, the blob count, 0
    mov     (%r15,%rax), %rax
    mov     %rax, (%r14)
    movq    $0, 16(%r14)
    xor     %eax, %eax
    LEAVE 144
8:  mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 144
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 144
SPEC_END node_publish_decode

/*
 * (gossip, block, sidecars, level, scratch): node.md, lantern_node_publish_check. rbx gossip,
 * rbp block, r12 sidecars, r13 level, r14 scratch, r15 a sidecar. Locals: L a Result, L+8 a root
 * (32), L+40 the sidecars' end, L+48 execution_valid 1, L+56 the scratch size, L+64 the counts
 * of seen's parts (40).
 */
SPEC_FUNCTION node_publish_check
    ENTER 112
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     (%r14), %rax
    mov     %rax, (L + 56)(%rsp)
    mov     NodeGossip_seen(%rbx), %rcx     # the counts of seen's parts, for a check that fails
    mov     (Seen_keys + 8)(%rcx), %rax
    mov     %rax, (L + 64)(%rsp)
    mov     (Seen_bits + 8)(%rcx), %rax
    mov     %rax, (L + 72)(%rsp)
    mov     (Seen_blocks + 8)(%rcx), %rax
    mov     %rax, (L + 80)(%rsp)
    mov     (Seen_headers + 8)(%rcx), %rax
    mov     %rax, (L + 88)(%rsp)
    mov     Seen_header_bytes(%rcx), %rax
    mov     %rax, (L + 96)(%rsp)
    movq    $GOSSIP_BEACON_BLOCK, NodeGossip_topic(%rbx)    # the beacon_block topic's checks
    movq    $0, NodeGossip_subnet(%rbx)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r14, %rdx
    call    publish_gossip
    test    %rax, %rax
    jnz     99f
.if FORK >= FORK_DENEB
    test    %r12, %r12                      # each sidecar's, on its subnet
    jz      5f
    mov     8(%r12), %r15
    add     %r12, %r15
    mov     16(%r12), %rax
    add     %r15, %rax
    mov     %rax, (L + 40)(%rsp)
1:  cmp     (L + 40)(%rsp), %r15
    jae     5f
    mov     8(%r15), %rax
    mov     (%r15,%rax), %rax               # its index, at byte 0 of its bytes
    mov     NodeGossip_config(%rbx), %rcx
.if FORK >= FORK_FULU
    mov     $GOSSIP_DATA_COLUMN_SIDECAR, %esi
    mov     CONFIG_DATA_COLUMN_SIDECAR_SUBNET_COUNT(%rcx), %rcx
.elseif FORK >= FORK_ELECTRA
    mov     $GOSSIP_BLOB_SIDECAR, %esi
    mov     CONFIG_BLOB_SIDECAR_SUBNET_COUNT_ELECTRA(%rcx), %rcx
.else
    mov     $GOSSIP_BLOB_SIDECAR, %esi
    mov     CONFIG_BLOB_SIDECAR_SUBNET_COUNT(%rcx), %rcx
.endif
    test    %rcx, %rcx
    jz      8f
    xor     %edx, %edx
    div     %rcx
    mov     %rsi, NodeGossip_topic(%rbx)
    mov     %rdx, NodeGossip_subnet(%rbx)
    mov     %rbx, %rdi
    mov     %r15, %rsi
    mov     %r14, %rdx
    call    publish_gossip
    test    %rax, %rax
    jnz     99f
    add     (%r15), %r15
    jmp     1b
5:
.endif
    cmp     $2, %r13                        # consensus: process_block on the parent's post-state at the slot
    jb      7f
    ADDRESS %rdi, lantern_type_SignedBeaconBlock
    mov     %rbp, %rsi
    mov     %r14, %rdx
    call    node_decode
    cmp     $1, %rax
    je      6f
    ja      8f
    mov     SignedBeaconBlock_message(%rdx), %rbp
    add     %rdx, %rbp                      # the block, decoded
    movq    $1, (L + 48)(%rsp)
    mov     NodeGossip_proposer(%rbx), %rdi
    mov     %rbp, %rsi
    lea     (L + 48)(%rsp), %rdx
    mov     NodeGossip_config(%rbx), %rcx
    mov     %r14, %r8
    lea     L(%rsp), %r9
    call    lantern_process_block
    test    %rax, %rax
    jnz     4f
    mov     L(%rsp), %rax
    test    %rax, %rax
    jnz     4f
    mov     NodeGossip_proposer(%rbx), %rdi
    mov     NodeGossip_config(%rbx), %rsi
    mov     CONFIG_STATE_CACHE(%rsi), %rsi
    mov     %r14, %rdx
    lea     (L + 8)(%rsp), %rcx
    call    lantern_state_root
    test    %rax, %rax
    jnz     4f
    lea     BeaconBlock_state_root(%rbp), %rdi
    lea     (L + 8)(%rsp), %rsi
    NE32    %rdi, %rsi, 3f
    jmp     7f
3:  mov     $LANTERN_INVALID_STATE_ROOT, %eax
4:  mov     (L + 56)(%rsp), %rcx
    mov     %rcx, (%r14)
    jmp     99f
7:  mov     (L + 56)(%rsp), %rcx
    mov     %rcx, (%r14)
    xor     %eax, %eax
    LEAVE 112
6:  mov     (L + 56)(%rsp), %rcx
    mov     %rcx, (%r14)
    mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    jmp     99f
8:  mov     (L + 56)(%rsp), %rcx
    mov     %rcx, (%r14)
    mov     $LANTERN_INVALID_ENCODING, %eax
99: mov     NodeGossip_seen(%rbx), %rcx     # a check that fails, or no room: seen as it was
    mov     (L + 64)(%rsp), %rdx
    mov     %rdx, (Seen_keys + 8)(%rcx)
    mov     (L + 72)(%rsp), %rdx
    mov     %rdx, (Seen_bits + 8)(%rcx)
    mov     (L + 80)(%rsp), %rdx
    mov     %rdx, (Seen_blocks + 8)(%rcx)
    mov     (L + 88)(%rsp), %rdx
    mov     %rdx, (Seen_headers + 8)(%rcx)
    mov     (L + 96)(%rsp), %rdx
    mov     %rdx, Seen_header_bytes(%rcx)
    LEAVE 112
SPEC_END node_publish_check

/*
 * L1: (gossip rdi, data rsi, scratch rdx) -> rax: LANTERN_OK when lantern_node_gossip of the data
 * holds, else its status or its result. Locals: a Result, a root (32), an index.
 */
LOCAL_FUNCTION publish_gossip
    FRAME 48
    mov     %rsp, %rcx
    lea     8(%rsp), %r8
    lea     40(%rsp), %r9
    call    lantern_node_gossip
    test    %rax, %rax
    jnz     9f
    mov     (%rsp), %rax
9:  UNFRAME 48
END_FUNCTION publish_gossip

.if FORK >= FORK_DENEB
/*
 * (body, json, scratch, out): node.md, lantern_node_publish_sidecars. rbx scratch, rbp out, r12 the
 * SignedBlockContents value, r13 its block's body, r14 the blob count, r15 a counter. Locals: L the
 * signed header (208), L+208 a GeneralizedIndex, L+216 a JsonFault (128), then a Branch of the
 * commitments' list (24 + 128), L+368 the KzgScratch, L+376 the cells, L+384 the stride, L+392 the
 * scratch size, L+400 a sidecar or a column.
 */
SPEC_FUNCTION node_publish_sidecars
    ENTER 416
    mov     %rdx, %rbx
    mov     %rcx, %rbp
    mov     (%rbx), %rax
    mov     %rax, (L + 392)(%rsp)
    mov     16(%rdi), %rcx                  # the SSZ bytes at the end of scratch: 24 + the body's length
    add     $(24 + 7), %rcx
    and     $-8, %rcx
    lea     64(%rcx), %rdx
    cmp     %rax, %rdx
    jae     8f
    sub     %rcx, %rax
    mov     %rax, (%rbx)
    lea     (%rbx,%rax), %r12
    mov     %rcx, (%r12)
    movq    $24, 8(%r12)
    movq    $0, 16(%r12)
    test    %rsi, %rsi
    jz      1f
    mov     %rdi, %rsi                      # JSON: its SSZ bytes
    ADDRESS %rdi, lantern_type_SignedBlockContents
    mov     %rbx, %rdx
    mov     %r12, %rcx
    lea     (L + 216)(%rsp), %r8
    CALL_GLOBAL lantern_json_decode
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8f
    test    %rax, %rax
    jnz     9f
    jmp     2f
1:  mov     8(%rdi), %rsi                   # SSZ: the bytes as they are
    mov     16(%rdi), %rdx
    mov     %rdx, 16(%r12)
    add     %rdi, %rsi
    lea     24(%r12), %rdi
    call    lantern_copy
2:  ADDRESS %rdi, lantern_type_SignedBlockContents   # its value
    mov     %r12, %rsi
    mov     %rbx, %rdx
    call    node_decode
    cmp     $1, %rax
    je      8f
    ja      9f
    mov     %rdx, %r12
    PART    %rsi, %rax, %r12, SignedBlockContents_signed_block   # compute_signed_block_header
    PART    %rdi, %rax, %rsi, SignedBeaconBlock_message
    mov     BeaconBlock_slot(%rdi), %rax
    mov     %rax, L(%rsp)
    mov     BeaconBlock_proposer_index(%rdi), %rax
    mov     %rax, (L + 8)(%rsp)
    PART    %r13, %rax, %rdi, BeaconBlock_body
    lea     BeaconBlock_parent_root(%rdi), %rax
    lea     (L + 16)(%rsp), %rcx
    COPY32  %rcx, %rax
    lea     BeaconBlock_state_root(%rdi), %rax
    lea     (L + 48)(%rsp), %rcx
    COPY32  %rcx, %rax
    lea     (L + 112)(%rsp), %rdi
    add     $SignedBeaconBlock_signature, %rsi
    mov     $96, %edx
    call    lantern_copy
    ADDRESS %rdi, lantern_type_BeaconBlockBody
    mov     %r13, %rsi
    mov     %rbx, %rdx
    lea     (L + 80)(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     8f
    mov     (BeaconBlockBody_blob_kzg_commitments + 8)(%r13), %r14   # the blob count
.if FORK >= FORK_FULU
    imul    $(PUB_CELL_BYTES + 96), %r14, %rax  # the stride: a ByteList of a column sidecar of the count
    add     $(PUB_COLUMN_FIXED + 24 + 7), %rax
    and     $-8, %rax
    mov     %rax, (L + 384)(%rsp)
    imul    $NUMBER_OF_COLUMNS, %rax, %rcx
    add     $24, %rcx
    cmp     (%rbp), %rcx
    ja      8f
    movq    $PUB_COMMITMENTS_GINDEX, (L + 208)(%rsp)    # the commitments' branch, the same for each column
    movq    $(24 + 32 * KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH), (L + 216)(%rsp)
    ADDRESS %rdi, lantern_type_BeaconBlockBody
    mov     %r13, %rsi
    lea     (L + 208)(%rsp), %rdx
    mov     %rbx, %rcx
    lea     (L + 216)(%rsp), %r8
    CALL_GLOBAL ssz_build_proof
    cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    je      8f
    test    %rax, %rax
    jnz     9f
    xor     %r15d, %r15d                    # each column: its fixed part, the commitments and its proofs
3:  cmp     $NUMBER_OF_COLUMNS, %r15
    jae     4f
    mov     (L + 384)(%rsp), %rcx
    imul    %r15, %rcx
    lea     24(%rbp,%rcx), %rcx
    mov     %rcx, (L + 400)(%rsp)
    mov     (L + 384)(%rsp), %rax
    mov     %rax, (%rcx)
    movq    $24, 8(%rcx)
    imul    $(PUB_CELL_BYTES + 96), %r14, %rax
    add     $PUB_COLUMN_FIXED, %rax
    mov     %rax, 16(%rcx)
    mov     %r15, 24(%rcx)                  # index
    mov     $PUB_COLUMN_FIXED, %eax         # the offsets of column, kzg_commitments, kzg_proofs
    mov     %eax, 32(%rcx)
    imul    $PUB_CELL_BYTES, %r14, %rdx
    add     %rdx, %rax
    mov     %eax, 36(%rcx)
    imul    $48, %r14, %rdx
    add     %rdx, %rax
    mov     %eax, 40(%rcx)
    lea     44(%rcx), %rdi                  # signed_block_header
    lea     L(%rsp), %rsi
    mov     $PUB_HEADER_BYTES, %edx
    call    lantern_copy
    mov     (L + 400)(%rsp), %rcx
    lea     (44 + PUB_HEADER_BYTES)(%rcx), %rdi     # kzg_commitments_inclusion_proof
    lea     (L + 216 + 24)(%rsp), %rsi
    mov     $(32 * KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH), %edx
    call    lantern_copy
    mov     (L + 400)(%rsp), %rcx           # kzg_commitments: the body's
    mov     36(%rcx), %edi
    lea     24(%rcx,%rdi), %rdi
    PART    %rsi, %rax, %r13, BeaconBlockBody_blob_kzg_commitments
    imul    $48, %r14, %rdx
    call    lantern_copy
    xor     %r8d, %r8d                      # kzg_proofs: proof c of each blob
31: cmp     %r14, %r8
    jae     32f
    mov     (L + 400)(%rsp), %rcx
    mov     40(%rcx), %edi
    lea     24(%rcx,%rdi), %rdi
    imul    $48, %r8, %rax
    add     %rax, %rdi
    PART    %rsi, %rax, %r12, SignedBlockContents_kzg_proofs
    imul    $CELLS_PER_EXT_BLOB, %r8, %rax
    add     %r15, %rax
    imul    $48, %rax, %rax
    add     %rax, %rsi
    movdqu  (%rsi), %xmm0
    movdqu  16(%rsi), %xmm1
    movdqu  32(%rsi), %xmm2
    movdqu  %xmm0, (%rdi)
    movdqu  %xmm1, 16(%rdi)
    movdqu  %xmm2, 32(%rdi)
    inc     %r8
    jmp     31b
32: inc     %r15
    jmp     3b
4:  mov     (%rbx), %rax                    # the cells of each blob: a KzgScratch and the cells at the end of scratch
    mov     $(CRYPTO_KZG_SCRATCH + CELLS_PER_EXT_BLOB * PUB_CELL_BYTES + 64), %ecx
    cmp     %rcx, %rax
    jb      8f
    sub     %rcx, %rax
    mov     %rax, (%rbx)
    lea     63(%rbx,%rax), %rax
    and     $-64, %rax
    movq    $CRYPTO_KZG_SCRATCH, (%rax)
    mov     %rax, (L + 368)(%rsp)
    add     $CRYPTO_KZG_SCRATCH, %rax
    mov     %rax, (L + 376)(%rsp)
    xor     %r15d, %r15d                    # blob b: its cells, then cell c to column c's place b
5:  cmp     %r14, %r15
    jae     7f
    PART    %rdi, %rax, %r12, SignedBlockContents_blobs
    imul    $PUB_BLOB_BYTES, %r15, %rax
    add     %rax, %rdi
    mov     (L + 368)(%rsp), %rsi
    mov     (L + 376)(%rsp), %rdx
    CALL_GLOBAL crypto_kzg_compute_cells
    cmp     $CRYPTO_BUFFER_TOO_SMALL, %rax
    je      8f
    test    %rax, %rax
    jnz     9f
    movq    $0, (L + 400)(%rsp)
6:  mov     (L + 400)(%rsp), %rax
    cmp     $NUMBER_OF_COLUMNS, %rax
    jae     61f
    imul    (L + 384)(%rsp), %rax
    lea     (24 + 24 + PUB_COLUMN_FIXED)(%rbp,%rax), %rdi
    imul    $PUB_CELL_BYTES, %r15, %rax
    add     %rax, %rdi
    mov     (L + 400)(%rsp), %rax
    imul    $PUB_CELL_BYTES, %rax, %rax
    mov     (L + 376)(%rsp), %rsi
    add     %rax, %rsi
    mov     $PUB_CELL_BYTES, %edx
    call    lantern_copy
    incq    (L + 400)(%rsp)
    jmp     6b
61: inc     %r15
    jmp     5b
7:  imul    $NUMBER_OF_COLUMNS, (L + 384)(%rsp), %rax
    mov     %rax, 16(%rbp)
.else
    imul    $(PUB_BLOB_SIDECAR + 24), %r14, %rax    # a BlobSidecar for each blob
    add     $24, %rax
    cmp     (%rbp), %rax
    ja      8f
    xor     %r15d, %r15d
3:  cmp     %r14, %r15
    jae     7f
    imul    $(PUB_BLOB_SIDECAR + 24), %r15, %rcx
    lea     24(%rbp,%rcx), %rcx
    mov     %rcx, (L + 400)(%rsp)
    movq    $(PUB_BLOB_SIDECAR + 24), (%rcx)
    movq    $24, 8(%rcx)
    movq    $PUB_BLOB_SIDECAR, 16(%rcx)
    mov     %r15, 24(%rcx)                  # index
    lea     32(%rcx), %rdi                  # blob
    PART    %rsi, %rax, %r12, SignedBlockContents_blobs
    imul    $PUB_BLOB_BYTES, %r15, %rax
    add     %rax, %rsi
    mov     $PUB_BLOB_BYTES, %edx
    call    lantern_copy
    mov     (L + 400)(%rsp), %rcx
    lea     (32 + PUB_BLOB_BYTES)(%rcx), %rdi   # kzg_commitment
    PART    %rsi, %rax, %r13, BeaconBlockBody_blob_kzg_commitments
    imul    $48, %r15, %rax
    add     %rax, %rsi
    mov     $48, %edx
    call    lantern_copy
    mov     (L + 400)(%rsp), %rcx
    lea     (32 + PUB_BLOB_BYTES + 48)(%rcx), %rdi  # kzg_proof
    PART    %rsi, %rax, %r12, SignedBlockContents_kzg_proofs
    imul    $48, %r15, %rax
    add     %rax, %rsi
    mov     $48, %edx
    call    lantern_copy
    mov     $(PUB_COMMITMENTS_GINDEX << 13), %eax   # the inclusion proof, its Branch header in the header's place
    add     %r15, %rax
    mov     %rax, (L + 208)(%rsp)
    mov     (L + 400)(%rsp), %r8
    add     $(32 + PUB_BLOB_BYTES + 96 + PUB_HEADER_BYTES - 24), %r8
    movq    $(24 + 32 * KZG_COMMITMENT_INCLUSION_PROOF_DEPTH), (%r8)
    ADDRESS %rdi, lantern_type_BeaconBlockBody
    mov     %r13, %rsi
    lea     (L + 208)(%rsp), %rdx
    mov     %rbx, %rcx
    CALL_GLOBAL ssz_build_proof
    cmp     $SSZ_BUFFER_TOO_SMALL, %rax
    je      8f
    test    %rax, %rax
    jnz     9f
    mov     (L + 400)(%rsp), %rcx
    lea     (32 + PUB_BLOB_BYTES + 96)(%rcx), %rdi  # signed_block_header, over the Branch header
    lea     L(%rsp), %rsi
    mov     $PUB_HEADER_BYTES, %edx
    call    lantern_copy
    inc     %r15
    jmp     3b
7:  imul    $(PUB_BLOB_SIDECAR + 24), %r14, %rax
    mov     %rax, 16(%rbp)
.endif
    mov     (L + 392)(%rsp), %rax
    mov     %rax, (%rbx)
    xor     %eax, %eax
    LEAVE 416
8:  mov     (L + 392)(%rsp), %rax
    mov     %rax, (%rbx)
    mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 416
9:  mov     (L + 392)(%rsp), %rax
    mov     %rax, (%rbx)
    mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 416
SPEC_END node_publish_sidecars
.endif
