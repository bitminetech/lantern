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
    jmp     98f
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
