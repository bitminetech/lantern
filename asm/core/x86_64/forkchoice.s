/*
 * Fork choice, x86-64. Requirements: docs/reference/fork-choice.md.
 * A ForkChoiceNode is the index of its BlockNode in the store.
 * An L0 helper returns its status in rax and its value in rdx.
 */

.set FC_ATTEST_EXTRA, IndexedAttestation__fixed + 8 + CIDX_BYTES

/* get_head: the flags of each node, a u64 each at the end of scratch. */
.set F_SUBTREE, 1          # in the subtree of the justified node
.set F_CHILD, 2            # has a child
.set F_VIABLE, 4           # in get_filtered_node_tree
.set F_CHILD_VIABLE, 8     # has a child in get_filtered_node_tree
.set F_OVERFLOW, 16        # its weight passed 2^64 - 1

.if BlockNode__mem != 224 || StoreValidator__mem != 32 || Checkpoint__mem != 40 || Checkpoint_root != 8
.error "the fork choice code assumes the layouts of include/lantern.inc"
.endif
.if PAYLOAD_STATUS_VALID != 0 || PAYLOAD_STATUS_INVALIDATED != 1
.error "the fork choice code tests PAYLOAD_STATUS_VALID as 0"
.endif
.if STORE_ACTIVE_UNSLASHED != 1 || STORE_EQUIVOCATING != 2 || STORE_IN_REGISTRY != 4
.error "the fork choice code tests the StoreValidator flags by bit number"
.endif
.if CRYPTO_KZG_CELL_SIZE != BYTES_PER_FIELD_ELEMENT * FIELD_ELEMENTS_PER_CELL || CRYPTO_KZG_CELL_SIZE != 2048
.error "a Cell of the spec is not a 2048 byte cell of asm-crypto"
.endif

/* ---------------------------------------------------------------- Macros */

/* dst = the address of node idx of store st. Uses r11. */
.macro NODE dst, st, idx
    imul    $BlockNode__mem, \idx, %r11
    add     Store_blocks(\st), %r11
    lea     (\st,%r11), \dst
.endm

/* rax = get_current_slot(store st); branch to fail when time_ms is before genesis_time_ms. Uses rdx. */
.macro STORE_SLOT st, fail
    mov     Store_time_ms(\st), %rax
    sub     Store_genesis_time_ms(\st), %rax
    jb      \fail
    xor     %edx, %edx
    divq    (Store_config + CONFIG_SLOT_DURATION_MS)(\st)
.endm

/* The 40-byte Checkpoint at dst = the one at src. Uses xmm0, xmm1, r11. */
.macro COPY40 dst, src
    COPY32  \dst, \src
    mov     32(\src), %r11
    mov     %r11, 32(\dst)
.endm

/* Branch to label when the Checkpoints at a and at b differ. Uses xmm0-xmm2, r11. */
.macro NE40 a, b, label
    NE32    \a, \b, \label
    mov     32(\a), %r11
    cmp     32(\b), %r11
    jne     \label
.endm

/* Branch to fail when the balances of store st are not those of its justified checkpoint. Uses xmm0-xmm2, r11. */
.macro NEED_BALANCES st, fail
    movdqu  Store_balances_checkpoint(\st), %xmm0
    movdqu  Store_justified_checkpoint(\st), %xmm1
    pcmpeqb %xmm1, %xmm0
    movdqu  (Store_balances_checkpoint + 16)(\st), %xmm1
    movdqu  (Store_justified_checkpoint + 16)(\st), %xmm2
    pcmpeqb %xmm2, %xmm1
    pand    %xmm1, %xmm0
    pmovmskb %xmm0, %r11d
    cmp     $0xffff, %r11d
    jne     \fail
    mov     (Store_balances_checkpoint + 32)(\st), %r11
    cmp     (Store_justified_checkpoint + 32)(\st), %r11
    jne     \fail
.endm

/* The Checkpoint at dst = the one at src when src's epoch is greater (lantern_update_checkpoints). Uses r10, r11, xmm0, xmm1. */
.macro RAISE dst, src
    mov     Checkpoint_epoch(\src), %r10
    cmp     Checkpoint_epoch(\dst), %r10
    jbe     98f
    COPY40  \dst, \src
98:
.endm

/* One u64 of a root comparison: the bytes at a + k and b + k as a big endian number. Uses r10, r11. */
.macro ROOT_STEP a, b, k, gt, le
    mov     \k(\a), %r10
    mov     \k(\b), %r11
    bswap   %r10
    bswap   %r11
    cmp     %r11, %r10
    ja      \gt
    jb      \le
.endm

/* Branch to gt when the root at a is greater than the root at b as a byte string, else to le. */
.macro ROOT_GT a, b, gt, le
    ROOT_STEP \a, \b, 0, \gt, \le
    ROOT_STEP \a, \b, 8, \gt, \le
    ROOT_STEP \a, \b, 16, \gt, \le
    ROOT_STEP \a, \b, 24, \gt, \le
    jmp     \le
.endm

/* dst = 1 when validator v is active at epoch and not slashed, else 0. */
.macro ACTIVE_UNSLASHED dst, v, epoch
    xor     \dst, \dst
    cmp     \epoch, Validator_activation_epoch(\v)
    ja      96f                             # activation_epoch <= epoch
    cmp     \epoch, Validator_exit_epoch(\v)
    jbe     96f                             # epoch < exit_epoch
    cmpb    $0, Validator_slashed(\v)
    jne     96f
    mov     $1, \dst
96:
.endm

/* ---------------------------------------------------------------- Nodes */

/* L0: rax = the node of the root at rsi in store rdi, or NODE_NONE. A leaf; uses rcx, rdx, r8-r11. */
LOCAL_FUNCTION lantern_find_node
    UNWIND_END_PROLOGUE
    PART    %rdx, %rcx, %rdi, Store_blocks
    mov     (%rsi), %r8
    mov     8(%rsi), %r9
    mov     16(%rsi), %r10
    mov     24(%rsi), %r11
1:  test    %rcx, %rcx                      # newest first
    jz      9f
    dec     %rcx
    imul    $BlockNode__mem, %rcx, %rax
    add     %rdx, %rax
    cmp     (%rax), %r8
    jne     1b
    cmp     8(%rax), %r9
    jne     1b
    cmp     16(%rax), %r10
    jne     1b
    cmp     24(%rax), %r11
    jne     1b
    mov     %rcx, %rax
    ret
9:  mov     $-1, %rax                       # NODE_NONE
    ret
END_FUNCTION lantern_find_node

/* L0: rax = status, rdx = get_ancestor(store rdi, node rsi, slot rdx). A leaf; uses rcx, rsi, r8. */
LOCAL_FUNCTION lantern_ancestor
    UNWIND_END_PROLOGUE
    mov     Store_blocks(%rdi), %rcx
    add     %rdi, %rcx
1:  imul    $BlockNode__mem, %rsi, %r8
    add     %rcx, %r8
    cmp     %rdx, BlockNode_slot(%r8)
    jbe     2f
    mov     BlockNode_parent(%r8), %rsi     # the parent, when it is in the store
    cmp     $-1, %rsi
    jne     1b
    mov     $LANTERN_INVALID_UNKNOWN_BLOCK, %eax
    ret
2:  mov     %rsi, %rdx
    xor     %eax, %eax
    ret
END_FUNCTION lantern_ancestor

/* L0: rax = status, rdx = the node of get_checkpoint_block(store rdi, node rsi, epoch rdx). A leaf. */
LOCAL_FUNCTION lantern_checkpoint_block
    UNWIND_END_PROLOGUE
    mov     %rdx, %rax
    shr     $(64 - LOG2_SLOTS_PER_EPOCH), %rax      # compute_start_slot_at_epoch(epoch) fits
    jnz     9f
    shl     $LOG2_SLOTS_PER_EPOCH, %rdx
    jmp     lantern_ancestor
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
END_FUNCTION lantern_checkpoint_block

SPEC_LEAF get_current_slot
    STORE_SLOT %rdi, 9f
    mov     %rax, (%rsi)
    RETURN_OK
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
SPEC_END get_current_slot

SPEC_LEAF get_current_store_epoch
    STORE_SLOT %rdi, 9f
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     %rax, (%rsi)
    RETURN_OK
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
SPEC_END get_current_store_epoch

SPEC_FUNCTION get_ancestor
    FRAME 16
    mov     %rcx, (%rsp)
    mov     (%rsi), %rsi
    mov     (%rdx), %rdx
    call    lantern_ancestor
    test    %rax, %rax
    jnz     1f
    mov     (%rsp), %rcx
    mov     %rdx, (%rcx)
1:  UNFRAME 16
SPEC_END get_ancestor

/* Locals: rsp+0 store, rsp+8 out, rsp+16 epoch. */
SPEC_FUNCTION get_checkpoint_block
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %rcx, 8(%rsp)
    mov     (%rdx), %rdx
    mov     %rdx, 16(%rsp)
    call    lantern_find_node
    cmp     $-1, %rax
    je      8f
    mov     %rax, %rsi
    mov     (%rsp), %rdi
    mov     16(%rsp), %rdx
    call    lantern_checkpoint_block
    test    %rax, %rax
    jnz     7f
    mov     (%rsp), %rdi
    NODE    %rsi, %rdi, %rdx
    mov     8(%rsp), %rcx
    COPY32  %rcx, %rsi
    xor     %eax, %eax
7:  UNFRAME 32
8:  mov     $LANTERN_INVALID_UNKNOWN_BLOCK, %eax
    UNFRAME 32
SPEC_END get_checkpoint_block

/* ---------------------------------------------------------------- Weights */

/*
 * L0: rax = status, rdx = get_attestation_score(store rdi, node rsi) with the store's balances.
 * A leaf; uses rcx, rdi, r8-r11. An overflow is reported after the sum, as the spec's Gwei does.
 */
LOCAL_FUNCTION lantern_attestation_score
    UNWIND_END_PROLOGUE
    mov     Store_blocks(%rdi), %r8
    add     %rdi, %r8                       # the nodes
    imul    $BlockNode__mem, %rsi, %r9
    mov     BlockNode_slot(%r8,%r9), %r9    # store.blocks[node.root].slot
    PART    %rcx, %r10, %rdi, Store_validators
    xor     %r11d, %r11d                    # the sum
    xor     %edi, %edi                      # carries
1:  test    %r10, %r10
    jz      5f
    dec     %r10
    mov     StoreValidator_flags(%rcx), %rax
    and     $(STORE_ACTIVE_UNSLASHED | STORE_EQUIVOCATING), %eax
    cmp     $STORE_ACTIVE_UNSLASHED, %eax   # unslashed and active, not equivocating
    jne     4f
    mov     StoreValidator_latest_node(%rcx), %rax
    cmp     $-1, %rax                       # index in store.latest_messages
    je      4f
    imul    $BlockNode__mem, %rax, %rdx     # not a vote for an INVALIDATED block (optimistic sync)
    cmpq    $PAYLOAD_STATUS_INVALIDATED, BlockNode_payload_status(%r8,%rdx)
    je      4f
2:  imul    $BlockNode__mem, %rax, %rdx     # is_ancestor(latest message node, node)
    add     %r8, %rdx
    cmp     %r9, BlockNode_slot(%rdx)
    jbe     3f
    mov     BlockNode_parent(%rdx), %rax
    cmp     $-1, %rax
    jne     2b
    mov     $LANTERN_INVALID_UNKNOWN_BLOCK, %eax
    ret
3:  cmp     %rsi, %rax
    jne     4f
    add     StoreValidator_effective_balance(%rcx), %r11
    adc     $0, %rdi
4:  add     $StoreValidator__mem, %rcx
    jmp     1b
5:  test    %rdi, %rdi
    jnz     9f
    mov     %r11, %rdx
    xor     %eax, %eax
    ret
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
END_FUNCTION lantern_attestation_score

/*
 * L0: rax = status, rdx = calculate_committee_fraction(justified state, percent rsi), from the
 * store's total balance. A leaf; uses rcx.
 */
LOCAL_FUNCTION lantern_committee_fraction
    UNWIND_END_PROLOGUE
    mov     Store_balances_total(%rdi), %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax     # committee_weight = total_balance // SLOTS_PER_EPOCH
    mul     %rsi
    jc      9f
    mov     $100, %ecx
    div     %rcx
    mov     %rax, %rdx
    xor     %eax, %eax
    ret
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
END_FUNCTION lantern_committee_fraction

/* L0: rax = status, rdx = get_weight(store rdi, node rsi) with the store's balances. rbx store, rbp node, r12 score. */
LOCAL_FUNCTION lantern_weight
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    call    lantern_attestation_score
    test    %rax, %rax
    jnz     7f
    mov     %rdx, %r12
    lea     Store_proposer_boost_root(%rbx), %rsi
    mov     (%rsi), %rax
    or      8(%rsi), %rax
    or      16(%rsi), %rax
    or      24(%rsi), %rax
    jz      6f                              # no proposer_boost_root: the attestation score
    mov     %rbx, %rdi
    call    lantern_find_node
    cmp     $-1, %rax
    je      8f
    NODE    %rcx, %rbx, %rax                # no boost from an INVALIDATED block (optimistic sync)
    cmpq    $PAYLOAD_STATUS_INVALIDATED, BlockNode_payload_status(%rcx)
    je      6f
    mov     %rax, %rsi                      # is_ancestor(store, proposer_boost_node, node)
    NODE    %rcx, %rbx, %rbp
    mov     BlockNode_slot(%rcx), %rdx
    mov     %rbx, %rdi
    call    lantern_ancestor
    test    %rax, %rax
    jnz     7f
    cmp     %rbp, %rdx
    jne     6f
    mov     %rbx, %rdi                      # get_proposer_score(store)
    mov     (Store_config + CONFIG_PROPOSER_SCORE_BOOST)(%rbx), %rsi
    call    lantern_committee_fraction
    test    %rax, %rax
    jnz     7f
    add     %rdx, %r12
    jc      9f
6:  mov     %r12, %rdx
    xor     %eax, %eax
7:  LEAVE 0
8:  mov     $LANTERN_INVALID_UNKNOWN_BLOCK, %eax
    LEAVE 0
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 0
END_FUNCTION lantern_weight

SPEC_FUNCTION get_weight
    FRAME 16
    mov     %rdx, (%rsp)
    NEED_BALANCES %rdi, 8f
    mov     (%rsi), %rsi
    call    lantern_weight
    test    %rax, %rax
    jnz     7f
    mov     (%rsp), %rcx
    mov     %rdx, (%rcx)
7:  UNFRAME 16
8:  mov     $LANTERN_NEED_JUSTIFIED_STATE, %eax
    UNFRAME 16
SPEC_END get_weight

/* ---------------------------------------------------------------- get_head */

/*
 * L0: get_filtered_node_tree(store rdi), with scratch rsi of S(1) for the node count: rax = status,
 * rdx = the flags of each node at the end of scratch (F_VIABLE: in the tree), rcx = the justified node.
 * rbx store, rbp flags, r12 node count, r13 nodes, r14 i; S7 justified node, S8 current epoch,
 * S9 correct_justified.
 */
LOCAL_FUNCTION lantern_filter_tree
    ENTER 16
    mov     %rdi, %rbx
    mov     (Store_blocks + 8)(%rbx), %r12
    mov     (%rsi), %rax                    # scratch: the flags at its end
    lea     (,%r12,8), %rcx
    lea     LIST_FIXED(%rcx), %rdx
    MOVQ    %r8, LANTERN_SCRATCH_FIXED
    add     %r8, %rdx
    cmp     %rdx, %rax
    jb      9f
    sub     %rcx, %rax
    lea     (%rsi,%rax), %rbp
    mov     Store_blocks(%rbx), %r13
    add     %rbx, %r13
    mov     %rbx, %rdi
    lea     (Store_justified_checkpoint + Checkpoint_root)(%rbx), %rsi
    call    lantern_find_node
    cmp     $-1, %rax
    je      8f
    mov     %rax, S7(%rsp)
    STORE_SLOT %rbx, 10f
    shr     $LOG2_SLOTS_PER_EPOCH, %rax     # get_current_store_epoch(store)
    mov     %rax, S8(%rsp)
    mov     %rbp, %rdi
    lea     (,%r12,8), %rsi
    call    lantern_zero
    mov     S7(%rsp), %rax                  # the subtree of the justified node: parents come first
    movq    $F_SUBTREE, (%rbp,%rax,8)
    lea     1(%rax), %r14
1:  cmp     %r12, %r14
    jae     2f
    imul    $BlockNode__mem, %r14, %rcx
    mov     BlockNode_parent(%r13,%rcx), %rdx
    cmp     $-1, %rdx
    je      15f
    cmpq    $PAYLOAD_STATUS_INVALIDATED, BlockNode_payload_status(%r13,%rcx)
    je      15f                             # removed from fork choice (optimistic sync)
    testq   $F_SUBTREE, (%rbp,%rdx,8)
    jz      15f
    orq     $F_CHILD, (%rbp,%rdx,8)
    movq    $F_SUBTREE, (%rbp,%r14,8)
15: inc     %r14
    jmp     1b
2:  lea     -1(%r12), %r14                  # filter_node_tree: children come before their parent
3:  cmp     S7(%rsp), %r14
    jl      6f
    mov     (%rbp,%r14,8), %rax
    test    $F_SUBTREE, %al
    jz      5f
    test    $F_CHILD, %al
    jz      31f
    test    $F_CHILD_VIABLE, %al            # with children: viable when a child is
    jz      5f
    jmp     4f
31: imul    $BlockNode__mem, %r14, %rcx     # a leaf
    add     %r13, %rcx
    mov     BlockNode_slot(%rcx), %rdx      # voting_source = get_voting_source(store, node.root)
    shr     $LOG2_SLOTS_PER_EPOCH, %rdx
    lea     BlockNode_justified_checkpoint(%rcx), %rsi
    lea     BlockNode_unrealized_justified_checkpoint(%rcx), %rdi
    cmp     %rdx, S8(%rsp)                  # current_epoch > block_epoch: the pulled up source
    cmova   %rdi, %rsi
    mov     Checkpoint_epoch(%rsi), %rsi
    movq    $1, S9(%rsp)                    # correct_justified
    mov     (Store_justified_checkpoint + Checkpoint_epoch)(%rbx), %rdx
    test    %rdx, %rdx                      # store.justified_checkpoint.epoch == GENESIS_EPOCH
    jz      34f
    cmp     %rdx, %rsi
    je      34f
    add     $2, %rsi                        # voting_source.epoch + 2 >= current_epoch
    jc      10f
    cmp     S8(%rsp), %rsi
    jae     34f
    movq    $0, S9(%rsp)
34: mov     %rbx, %rdi                      # finalized_checkpoint_block
    mov     %r14, %rsi
    mov     (Store_finalized_checkpoint + Checkpoint_epoch)(%rbx), %rdx
    call    lantern_checkpoint_block
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (Store_finalized_checkpoint + Checkpoint_epoch)(%rbx)
    je      35f                             # correct_finalized
    NODE    %rcx, %rbx, %rdx
    lea     (Store_finalized_checkpoint + Checkpoint_root)(%rbx), %rsi
    NE32    %rcx, %rsi, 5f
35: cmpq    $0, S9(%rsp)
    je      5f
4:  orq     $F_VIABLE, (%rbp,%r14,8)        # viable: so is its parent
    cmp     S7(%rsp), %r14
    je      5f
    imul    $BlockNode__mem, %r14, %rcx
    mov     BlockNode_parent(%r13,%rcx), %rdx
    orq     $F_CHILD_VIABLE, (%rbp,%rdx,8)
5:  dec     %r14
    jmp     3b
6:  mov     %rbp, %rdx
    mov     S7(%rsp), %rcx
    xor     %eax, %eax
7:  LEAVE 16
8:  mov     $LANTERN_INVALID_UNKNOWN_BLOCK, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
10: mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 16
END_FUNCTION lantern_filter_tree

/*
 * L1: the weights of all nodes at once (fork-choice.md, lantern_get_head): store rdi, weights rsi
 * and flags rdx, 8 bytes a node: rax = the status of the proposer boost, LANTERN_OK or a failure
 * of its node or get_proposer_score. Each weight is get_weight of its node; a sum past 2^64 - 1
 * sets F_OVERFLOW in the flags of the node and of each node above it. rbx store, rbp flags, r12
 * node count, r13 nodes, r14 i, S8 the weights. Locals: L the status of the boost.
 */
LOCAL_FUNCTION lantern_weights
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, S8(%rsp)
    mov     %rdx, %rbp
    mov     (Store_blocks + 8)(%rbx), %r12
    mov     Store_blocks(%rbx), %r13
    add     %rbx, %r13
    mov     %rsi, %rdi
    mov     %r12, %rsi
    shl     $3, %rsi
    call    lantern_zero
    PART    %rcx, %r10, %rbx, Store_validators  # each counted latest message, on its node
    mov     S8(%rsp), %r11
1:  test    %r10, %r10
    jz      3f
    dec     %r10
    mov     StoreValidator_flags(%rcx), %rax
    and     $(STORE_ACTIVE_UNSLASHED | STORE_EQUIVOCATING), %eax
    cmp     $STORE_ACTIVE_UNSLASHED, %eax   # unslashed and active, not equivocating
    jne     2f
    mov     StoreValidator_latest_node(%rcx), %rax
    cmp     $-1, %rax
    je      2f
    imul    $BlockNode__mem, %rax, %rdx     # not a vote for an INVALIDATED block (optimistic sync)
    cmpq    $PAYLOAD_STATUS_INVALIDATED, BlockNode_payload_status(%r13,%rdx)
    je      2f
    mov     StoreValidator_effective_balance(%rcx), %rdx
    add     %rdx, (%r11,%rax,8)
    jnc     2f
    orq     $F_OVERFLOW, (%rbp,%rax,8)
2:  add     $StoreValidator__mem, %rcx
    jmp     1b
3:  movq    $0, L(%rsp)                     # the proposer boost, on its node
    lea     Store_proposer_boost_root(%rbx), %rsi
    mov     (%rsi), %rax
    or      8(%rsi), %rax
    or      16(%rsi), %rax
    or      24(%rsi), %rax
    jz      4f
    mov     %rbx, %rdi
    call    lantern_find_node
    cmp     $-1, %rax
    jne     31f
    movq    $LANTERN_INVALID_UNKNOWN_BLOCK, L(%rsp)
    jmp     4f
31: mov     %rax, %r14
    imul    $BlockNode__mem, %r14, %rcx     # no boost from an INVALIDATED block (optimistic sync)
    cmpq    $PAYLOAD_STATUS_INVALIDATED, BlockNode_payload_status(%r13,%rcx)
    je      4f
    mov     %rbx, %rdi                      # get_proposer_score(store)
    mov     (Store_config + CONFIG_PROPOSER_SCORE_BOOST)(%rbx), %rsi
    call    lantern_committee_fraction
    test    %rax, %rax
    jz      32f
    mov     %rax, L(%rsp)
    jmp     4f
32: mov     S8(%rsp), %rax
    add     %rdx, (%rax,%r14,8)
    jnc     4f
    orq     $F_OVERFLOW, (%rbp,%r14,8)
4:  lea     -1(%r12), %r14                  # from the last node to the first: onto the parent
    mov     S8(%rsp), %r11
41: test    %r14, %r14
    jz      60f
    imul    $BlockNode__mem, %r14, %rcx
    mov     BlockNode_parent(%r13,%rcx), %rcx
    cmp     $-1, %rcx
    je      44f
    mov     (%rbp,%r14,8), %rax
    and     $F_OVERFLOW, %eax
    or      %rax, (%rbp,%rcx,8)
    mov     (%r11,%r14,8), %rax
    add     %rax, (%r11,%rcx,8)
    jnc     44f
    orq     $F_OVERFLOW, (%rbp,%rcx,8)
44: dec     %r14
    jmp     41b
60: mov     L(%rsp), %rax
    LEAVE 16
END_FUNCTION lantern_weights

/*
 * L0: rax = status, rdx = get_head(store rdi), with scratch rsi of S(2) for the node count. The
 * weights of all nodes at once (fork-choice.md, lantern_get_head): each latest message's balance on
 * its node, the boost on the boost node, then each node's weight onto its parent's.
 * rbx store, rbp flags, r12 node count, r13 nodes, r14 i, r15 head; S7 justified node, S8 the
 * weights, S9 best child, S10 best weight. Locals: L the status of the boost.
 */
LOCAL_FUNCTION lantern_head
    ENTER 16
    mov     %rdi, %rbx
    mov     (Store_blocks + 8)(%rbx), %r12
    mov     (%rsi), %rax                    # the weights: 8 bytes a node, before lantern_filter_tree's flags
    mov     %r12, %rcx
    shl     $4, %rcx
    lea     (LIST_FIXED + LANTERN_SCRATCH_FIXED)(%rcx), %rdx
    cmp     %rdx, %rax
    jb      9f
    mov     %r12, %rcx
    shl     $4, %rcx
    sub     %rcx, %rax
    add     %rsi, %rax
    mov     %rax, S8(%rsp)
    mov     %rbx, %rdi
    call    lantern_filter_tree                     # nodes = get_filtered_node_tree(store)
    test    %rax, %rax
    jnz     7f
    mov     %rdx, %rbp
    mov     %rcx, S7(%rsp)
    mov     Store_blocks(%rbx), %r13
    add     %rbx, %r13
    mov     %rbx, %rdi                      # the weights of all nodes at once
    mov     S8(%rsp), %rsi
    mov     %rbp, %rdx
    call    lantern_weights
    mov     %rax, L(%rsp)
60: mov     S7(%rsp), %r15                  # head = the justified node
61: movq    $-1, S9(%rsp)                   # the best child so far
    movq    $0, S10(%rsp)
    lea     1(%r15), %r14
62: cmp     %r12, %r14
    jae     65f
    imul    $BlockNode__mem, %r14, %rcx
    cmp     %r15, BlockNode_parent(%r13,%rcx)
    jne     64f
    testq   $F_VIABLE, (%rbp,%r14,8)        # a child in nodes
    jz      64f
    mov     L(%rsp), %rax                   # its weight: a failure of the boost, or a sum past 2^64 - 1
    test    %rax, %rax
    jnz     7f
    testq   $F_OVERFLOW, (%rbp,%r14,8)
    jnz     8f
    mov     S8(%rsp), %rdx
    mov     (%rdx,%r14,8), %rdx
    cmpq    $-1, S9(%rsp)
    je      63f
    cmp     S10(%rsp), %rdx                 # max by (weight, root)
    ja      63f
    jb      64f
    imul    $BlockNode__mem, %r14, %rcx
    add     %r13, %rcx
    mov     S9(%rsp), %rsi
    imul    $BlockNode__mem, %rsi, %rsi
    add     %r13, %rsi
    ROOT_GT %rcx, %rsi, 63f, 64f
63: mov     %r14, S9(%rsp)
    mov     %rdx, S10(%rsp)
64: inc     %r14
    jmp     62b
65: mov     S9(%rsp), %rax
    cmp     $-1, %rax
    je      66f
    mov     %rax, %r15
    jmp     61b
66: mov     %r15, %rdx
    xor     %eax, %eax
7:  LEAVE 16
8:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
END_FUNCTION lantern_head

/* rbx store, rbp out. */
SPEC_FUNCTION get_filtered_node_tree
    ENTER 0
    mov     %rdi, %rbx
    mov     %rdx, %rbp
    call    lantern_filter_tree
    test    %rax, %rax
    jnz     7f
    mov     (Store_blocks + 8)(%rbx), %rcx
    xor     %r8d, %r8d                      # the nodes in the tree
    xor     %r9d, %r9d
1:  cmp     %rcx, %r9
    jae     2f
    mov     (%rdx,%r9,8), %rax
    and     $F_VIABLE, %eax
    shr     $2, %eax
    add     %rax, %r8
    inc     %r9
    jmp     1b
2:  lea     LIST_FIXED(,%r8,8), %rax
    cmp     %rax, (%rbp)
    jb      9f
    movq    $LIST_FIXED, LIST_OFFSET(%rbp)
    mov     %r8, LIST_COUNT(%rbp)
    lea     LIST_FIXED(%rbp), %rsi
    xor     %r9d, %r9d
3:  cmp     %rcx, %r9
    jae     4f
    testq   $F_VIABLE, (%rdx,%r9,8)
    jz      31f
    mov     %r9, (%rsi)
    add     $8, %rsi
31: inc     %r9
    jmp     3b
4:  xor     %eax, %eax
7:  LEAVE 0
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
SPEC_END get_filtered_node_tree

SPEC_FUNCTION get_head
    FRAME 16
    mov     %rdx, (%rsp)
    NEED_BALANCES %rdi, 8f
    call    lantern_head
    test    %rax, %rax
    jnz     7f
    mov     (%rsp), %rcx
    mov     %rdx, (%rcx)
7:  UNFRAME 16
8:  mov     $LANTERN_NEED_JUSTIFIED_STATE, %eax
    UNFRAME 16
SPEC_END get_head

/* ---------------------------------------------------------------- Checkpoints and time */

/* L0: lantern_update_checkpoints(store rdi, justified rsi, finalized rdx). A leaf; uses rax, r10, r11, xmm0, xmm1. */
LOCAL_FUNCTION lantern_update_checkpoints
    UNWIND_END_PROLOGUE
    lea     Store_justified_checkpoint(%rdi), %rax
    RAISE   %rax, %rsi
    lea     Store_finalized_checkpoint(%rdi), %rax
    RAISE   %rax, %rdx
    ret
END_FUNCTION lantern_update_checkpoints

/* L0: lantern_update_unrealized_checkpoints(store rdi, justified rsi, finalized rdx). A leaf; uses rax, r10, r11, xmm0, xmm1. */
LOCAL_FUNCTION lantern_update_unrealized_checkpoints
    UNWIND_END_PROLOGUE
    lea     Store_unrealized_justified_checkpoint(%rdi), %rax
    RAISE   %rax, %rsi
    lea     Store_unrealized_finalized_checkpoint(%rdi), %rax
    RAISE   %rax, %rdx
    ret
END_FUNCTION lantern_update_unrealized_checkpoints

/* L0: lantern_on_tick_per_slot(store rdi, time_ms rsi), with time_ms not before genesis_time_ms. A leaf. */
LOCAL_FUNCTION lantern_on_tick_per_slot
    UNWIND_END_PROLOGUE
    STORE_SLOT %rdi, 9f                     # previous_slot
    mov     %rax, %rcx
    mov     %rsi, Store_time_ms(%rdi)
    STORE_SLOT %rdi, 9f                     # current_slot
    cmp     %rcx, %rax
    jbe     9f
    pxor    %xmm0, %xmm0                    # a new slot: proposer_boost_root = Root()
    movdqu  %xmm0, Store_proposer_boost_root(%rdi)
    movdqu  %xmm0, (Store_proposer_boost_root + 16)(%rdi)
    test    $(SLOTS_PER_EPOCH - 1), %rax    # a new epoch: pull up the unrealized checkpoints
    jnz     9f
    lea     Store_unrealized_justified_checkpoint(%rdi), %rsi
    lea     Store_unrealized_finalized_checkpoint(%rdi), %rdx
    jmp     lantern_update_checkpoints
9:  ret
END_FUNCTION lantern_on_tick_per_slot

/* rbx store, rbp time_ms, r12 result, r13 tick slot, r14 genesis_time_ms, r15 SLOT_DURATION_MS. */
SPEC_FUNCTION on_tick
    ENTER 0
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    movq    $0, (%r12)
    mov     Store_genesis_time_ms(%rbx), %r14
    mov     (Store_config + CONFIG_SLOT_DURATION_MS)(%rbx), %r15
    mov     %rbp, %rax                      # tick_slot = compute_slot_at_time_ms(genesis_time_ms, time_ms)
    sub     %r14, %rax
    jb      6f
    xor     %edx, %edx
    div     %r15
    mov     %rax, %r13
1:  STORE_SLOT %rbx, 6f                     # catch up slot by slot
    cmp     %r13, %rax
    jae     2f
    inc     %rax
    imul    %r15, %rax                      # compute_time_at_slot_ms(genesis_time_ms, next_slot)
    lea     (%rax,%r14), %rsi
    mov     %rbx, %rdi
    call    lantern_on_tick_per_slot
    jmp     1b
2:  mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    lantern_on_tick_per_slot
    xor     %eax, %eax
    LEAVE 0
6:  movq    $LANTERN_INVALID_OVERFLOW, (%r12)
    xor     %eax, %eax
    LEAVE 0
SPEC_END on_tick

/* ---------------------------------------------------------------- The store */

/*
 * rdi store, rsi state; r12 entries, r13 entry count, r14 validators, r15 validator count,
 * rcx epoch, rax total, rdx i, r8 cursor.
 */
SPEC_FUNCTION store_justified_checkpoint_state
    ENTER 0
    PART    %r12, %r13, %rdi, Store_validators
    PART    %r14, %r15, %rsi, BeaconState_validators
    cmp     %r13, %r15
    ja      9f
    mov     BeaconState_slot(%rsi), %rcx
    shr     $LOG2_SLOTS_PER_EPOCH, %rcx     # get_current_epoch(state)
    xor     %eax, %eax
    xor     %edx, %edx
    mov     %r14, %r8
1:  cmp     %r15, %rdx                      # get_total_balance of the active unslashed, before any change
    jae     2f
    ACTIVE_UNSLASHED %r9, %r8, %rcx
    test    %r9, %r9
    jz      11f
    add     Validator_effective_balance(%r8), %rax
    jc      8f
11: add     $Validator__mem, %r8
    inc     %rdx
    jmp     1b
2:  MOVQ    %r9, EFFECTIVE_BALANCE_INCREMENT
    cmp     %r9, %rax
    cmovb   %r9, %rax
    mov     %rax, Store_balances_total(%rdi)
    xor     %edx, %edx
3:  cmp     %r13, %rdx
    jae     5f
    mov     StoreValidator_flags(%r12), %rsi
    and     $STORE_EQUIVOCATING, %esi
    xor     %eax, %eax
    cmp     %r15, %rdx
    jae     4f
    ACTIVE_UNSLASHED %r9, %r14, %rcx
    or      $STORE_IN_REGISTRY, %rsi
    or      %r9, %rsi
    mov     Validator_effective_balance(%r14), %rax
    add     $Validator__mem, %r14
4:  mov     %rax, StoreValidator_effective_balance(%r12)
    mov     %rsi, StoreValidator_flags(%r12)
    add     $StoreValidator__mem, %r12
    inc     %rdx
    jmp     3b
5:  lea     Store_balances_checkpoint(%rdi), %rax
    lea     Store_justified_checkpoint(%rdi), %rcx
    COPY40  %rax, %rcx
    xor     %eax, %eax
    LEAVE 0
8:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 0
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
SPEC_END store_justified_checkpoint_state

/*
 * rbx anchor state, rbp anchor block, r12 config, r13 room, r14 scratch, r15 store;
 * S9 anchor epoch. Locals: L state root (32), L+32 anchor root (32), L+64 size.
 */
SPEC_FUNCTION get_forkchoice_store
    ENTER 80
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r9, %r15
    cmpq    $0, (%r13)
    je      9f
    mov     8(%r13), %rax
    cmp     (BeaconState_validators + 8)(%rbx), %rax
    jb      9f
    mov     %r13, %rdi
    lea     (L + 64)(%rsp), %rsi
    CALL_GLOBAL lantern_store_size
    test    %rax, %rax
    jnz     9f
    mov     (L + 64)(%rsp), %rax
    cmp     %rax, (%r15)
    jb      9f
    MOVQ    %rax, LANTERN_SCRATCH_FIXED
    cmp     %rax, (%r14)
    jb      9f
    ADDRESS %rdi, lantern_type_BeaconState  # assert anchor_block.state_root == hash_tree_root(anchor_state)
    mov     %rbx, %rsi
    mov     %r14, %rdx
    lea     L(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    lea     BeaconBlock_state_root(%rbp), %rax
    lea     L(%rsp), %rcx
    NE32    %rax, %rcx, 6f
    ADDRESS %rdi, lantern_type_BeaconBlock  # anchor_root = hash_tree_root(anchor_block)
    mov     %rbp, %rsi
    mov     %r14, %rdx
    lea     (L + 32)(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    mov     BeaconState_genesis_time(%rbx), %rax    # genesis_time_ms = seconds_to_milliseconds(genesis_time)
    mov     $1000, %ecx
    mul     %rcx
    jnc     1f
    mov     $-1, %rax                       # UINT64_MAX when it does not fit
1:  mov     %rax, %r8
    mov     BeaconState_slot(%rbx), %rax    # time_ms = compute_time_at_slot_ms(genesis_time_ms, anchor_state.slot)
    mov     %rax, %r9
    mulq    CONFIG_SLOT_DURATION_MS(%r12)
    jc      5f
    add     %r8, %rax
    jc      5f
    mov     %rax, Store_time_ms(%r15)
    mov     %r8, Store_genesis_time_ms(%r15)
    shr     $LOG2_SLOTS_PER_EPOCH, %r9      # anchor_epoch = get_current_epoch(anchor_state)
    mov     %r9, S9(%rsp)
    lea     (L + 32)(%rsp), %rcx            # the four checkpoints: (anchor_epoch, anchor_root)
    mov     %r9, Store_justified_checkpoint(%r15)
    lea     (Store_justified_checkpoint + Checkpoint_root)(%r15), %rax
    COPY32  %rax, %rcx
    mov     %r9, Store_finalized_checkpoint(%r15)
    lea     (Store_finalized_checkpoint + Checkpoint_root)(%r15), %rax
    COPY32  %rax, %rcx
    mov     %r9, Store_unrealized_justified_checkpoint(%r15)
    lea     (Store_unrealized_justified_checkpoint + Checkpoint_root)(%r15), %rax
    COPY32  %rax, %rcx
    mov     %r9, Store_unrealized_finalized_checkpoint(%r15)
    lea     (Store_unrealized_finalized_checkpoint + Checkpoint_root)(%r15), %rax
    COPY32  %rax, %rcx
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, Store_proposer_boost_root(%r15)
    movdqu  %xmm0, (Store_proposer_boost_root + 16)(%r15)
    movq    $STORE_FIXED, Store_blocks(%r15)        # the parts: the anchor node, then the validators
    movq    $1, (Store_blocks + 8)(%r15)
    imul    $BlockNode__mem, (%r13), %rax
    add     $STORE_FIXED, %rax
    mov     %rax, Store_validators(%r15)
    mov     8(%r13), %rax
    mov     %rax, (Store_validators + 8)(%r15)
    lea     Store_config(%r15), %rdi
    mov     %r12, %rsi
    mov     $CONFIG_SIZE, %edx
    call    lantern_copy
    lea     STORE_FIXED(%r15), %rax         # blocks = {anchor_root: anchor_block}
    lea     (L + 32)(%rsp), %rcx
    COPY32  %rax, %rcx
    lea     BlockNode_parent_root(%rax), %rdx
    lea     BeaconBlock_parent_root(%rbp), %rcx
    COPY32  %rdx, %rcx
    mov     BeaconBlock_slot(%rbp), %rcx
    mov     %rcx, BlockNode_slot(%rax)
    mov     BeaconBlock_proposer_index(%rbp), %rcx
    mov     %rcx, BlockNode_proposer_index(%rax)
    movq    $-1, BlockNode_parent(%rax)
    lea     BlockNode_justified_checkpoint(%rax), %rdx      # block_states[anchor_root].current_justified_checkpoint
    lea     BeaconState_current_justified_checkpoint(%rbx), %rcx
    COPY40  %rdx, %rcx
    mov     (BeaconState_finalized_checkpoint + Checkpoint_epoch)(%rbx), %rcx   # and its finalized_checkpoint.epoch
    mov     %rcx, BlockNode_finalized_epoch(%rax)
    mov     S9(%rsp), %rcx                  # unrealized_justifications
    mov     %rcx, BlockNode_unrealized_justified_checkpoint(%rax)
    lea     (BlockNode_unrealized_justified_checkpoint + Checkpoint_root)(%rax), %rdx
    lea     (L + 32)(%rsp), %rcx
    COPY32  %rdx, %rcx
    movq    $0, BlockNode_timely(%rax)
.if FORK >= FORK_BELLATRIX
    mov     BeaconState_latest_execution_payload_header(%rbx), %rsi    # the anchor state's payload hash, VALID
    lea     ExecutionPayloadHeader_block_hash(%rbx,%rsi), %rsi
    lea     BlockNode_block_hash(%rax), %rdx
    COPY32  %rdx, %rsi
.else
    .irp k, 0, 8, 16, 24
    movq    $0, (BlockNode_block_hash + \k)(%rax)  # no payload before bellatrix: a zero hash
    .endr
.endif
    movq    $PAYLOAD_STATUS_VALID, BlockNode_payload_status(%rax)
    PART    %rax, %rcx, %r15, Store_validators      # latest_messages = {}
2:  test    %rcx, %rcx
    jz      3f
    movq    $0, StoreValidator_latest_epoch(%rax)
    movq    $-1, StoreValidator_latest_node(%rax)
    movq    $0, StoreValidator_effective_balance(%rax)
    movq    $0, StoreValidator_flags(%rax)
    add     $StoreValidator__mem, %rax
    dec     %rcx
    jmp     2b
3:  mov     %r15, %rdi                      # checkpoint_states = {justified_checkpoint: anchor_state}
    mov     %rbx, %rsi
    call    lantern_store_justified_checkpoint_state
7:  LEAVE 80
5:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 80
6:  mov     $LANTERN_INVALID_ANCHOR, %eax
    LEAVE 80
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 80
SPEC_END get_forkchoice_store

/* ---------------------------------------------------------------- Attestations */

/*
 * L0: rax = validate_on_attestation(store rdi, data rsi, is_from_block rdx as a value), as a
 * status; rdx = the node of the head vote. rbx store, rbp data, r12 target node, r13 head node.
 */
LOCAL_FUNCTION lantern_validate_attestation
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     (AttestationData_target + Checkpoint_epoch)(%rbp), %rcx
    test    %rdx, %rdx
    jnz     1f
    STORE_SLOT %rbx, 10f                    # validate_target_epoch_against_current_time
    shr     $LOG2_SLOTS_PER_EPOCH, %rax     # current_epoch
    cmp     %rax, %rcx
    je      1f
    test    %rax, %rax                      # previous_epoch = saturating_sub(current_epoch, 1)
    jz      6f
    dec     %rax
    cmp     %rax, %rcx
    jne     6f
1:  mov     AttestationData_slot(%rbp), %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax     # target.epoch == compute_epoch_at_slot(slot)
    cmp     %rax, %rcx
    jne     6f
    mov     %rbx, %rdi                      # target.root in store.blocks
    lea     (AttestationData_target + Checkpoint_root)(%rbp), %rsi
    call    lantern_find_node
    cmp     $-1, %rax
    je      8f
    mov     %rax, %r12
    mov     %rbx, %rdi                      # beacon_block_root in store.blocks
    lea     AttestationData_beacon_block_root(%rbp), %rsi
    call    lantern_find_node
    cmp     $-1, %rax
    je      8f
    mov     %rax, %r13
    NODE    %rax, %rbx, %r13
    mov     BlockNode_slot(%rax), %rax
    cmp     AttestationData_slot(%rbp), %rax
    ja      5f
    mov     %rbx, %rdi                      # target.root == get_checkpoint_block(beacon_block_root, target.epoch)
    mov     %r13, %rsi
    mov     (AttestationData_target + Checkpoint_epoch)(%rbp), %rdx
    call    lantern_checkpoint_block
    test    %rax, %rax
    jnz     7f
    cmp     %r12, %rdx
    jne     6f
    mov     AttestationData_slot(%rbp), %rcx        # get_current_slot(store) >= slot + 1
    add     $1, %rcx
    jc      10f
    STORE_SLOT %rbx, 10f
    cmp     %rcx, %rax
    jb      4f
    mov     %r13, %rdx
    xor     %eax, %eax
7:  LEAVE 0
4:  mov     $LANTERN_INVALID_FUTURE_SLOT, %eax
    LEAVE 0
5:  mov     $LANTERN_INVALID_ATTESTATION_SLOT, %eax
    LEAVE 0
6:  mov     $LANTERN_INVALID_ATTESTATION_TARGET, %eax
    LEAVE 0
8:  mov     $LANTERN_INVALID_UNKNOWN_BLOCK, %eax
    LEAVE 0
10: mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 0
END_FUNCTION lantern_validate_attestation

SPEC_FUNCTION validate_on_attestation
    FRAME 0
    add     $Attestation_data, %rsi
    mov     (%rdx), %rdx
    call    lantern_validate_attestation
    UNFRAME 0
SPEC_END validate_on_attestation

/* Local: rsp+0 the start slot. */
SPEC_FUNCTION store_target_checkpoint_state
    FRAME 16
    mov     Checkpoint_epoch(%rsi), %rax
    mov     %rax, %r9
    shr     $(64 - LOG2_SLOTS_PER_EPOCH), %r9
    jnz     6f
    shl     $LOG2_SLOTS_PER_EPOCH, %rax     # compute_start_slot_at_epoch(target.epoch)
    mov     %rax, (%rsp)
    cmp     %rax, BeaconState_slot(%rdi)
    jae     5f
    mov     %rsp, %rsi                      # process_slots(base_state, start slot)
    call    lantern_process_slots
    UNFRAME 16
5:  movq    $0, (%r8)
    xor     %eax, %eax
    UNFRAME 16
6:  movq    $LANTERN_INVALID_OVERFLOW, (%r8)
    xor     %eax, %eax
    UNFRAME 16
SPEC_END store_target_checkpoint_state

/*
 * rbx store, rbp attestation, r12 is_from_block, r13 target state, r14 scratch, r15 result;
 * S7 scratch size for callees, S8 indexed attestation, S9 head vote node. Locals: L valid.
 */
SPEC_FUNCTION on_attestation
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r9, %r15
    movq    $0, (%r15)
    NEED_SCRATCH_B %r14, %r13, 8, FC_ATTEST_EXTRA, 9f
    mov     (%r14), %rax                    # own scratch at the end: the indexed attestation
    mov     (BeaconState_validators + 8)(%r13), %rcx
    lea     (IndexedAttestation__fixed + 8)(,%rcx,8), %rcx
    sub     %rcx, %rax
    mov     %rax, S7(%rsp)
    lea     (%r14,%rax), %rdx
    mov     %rdx, S8(%rsp)
    mov     %rcx, (%rdx)
    mov     %rbx, %rdi                      # validate_on_attestation(store, attestation, is_from_block)
    lea     Attestation_data(%rbp), %rsi
    mov     (%r12), %rdx
    call    lantern_validate_attestation
    test    %rax, %rax
    jnz     6f
    mov     %rdx, S9(%rsp)
    mov     S7(%rsp), %rax                  # get_indexed_attestation(target_state, attestation)
    mov     %rax, (%r14)
    mov     %r13, %rdi
    mov     %rbp, %rsi
    mov     %r14, %rcx
    mov     S8(%rsp), %r8
    mov     (Store_config + CONFIG_COMMITTEE_CACHE)(%rbx), %rdx
    call    lantern_get_indexed_attestation
    CHECK_STATUS %r15, 7f, 8f
    mov     S7(%rsp), %rax                  # assert is_valid_indexed_attestation(target_state, indexed_attestation)
    mov     %rax, (%r14)
    mov     %r13, %rdi
    mov     S8(%rsp), %rsi
    mov     %r14, %rcx
    lea     L(%rsp), %r8
    mov     (Store_config + CONFIG_PUBKEY_CACHE)(%rbx), %rdx
    mov     %rbp, %r9                       # with the attestation and its CommitteeCache: key sums
    mov     (Store_config + CONFIG_COMMITTEE_CACHE)(%rbx), %r10
    call    lantern_indexed_attestation_valid
    CHECK_STATUS %r15, 7f, 8f
    mov     $LANTERN_INVALID_ATTESTATION, %eax
    cmpq    $0, L(%rsp)
    je      6f
    mov     S8(%rsp), %rax                  # update_latest_messages
    PART    %rsi, %rcx, %rax, IndexedAttestation_attesting_indices
    PART    %rdi, %rdx, %rbx, Store_validators
    test    %rcx, %rcx
    jz      8f
    mov     -8(%rsi,%rcx,8), %rax           # the indices ascend: the last needs an entry
    cmp     %rdx, %rax
    jae     9f
    mov     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%rbp), %r8
    mov     S9(%rsp), %r9
1:  test    %rcx, %rcx
    jz      8f
    mov     (%rsi), %rax
    add     $8, %rsi
    shl     $5, %rax
    add     %rdi, %rax
    testq   $STORE_EQUIVOCATING, StoreValidator_flags(%rax)     # in store.equivocating_indices
    jnz     2f
    cmpq    $-1, StoreValidator_latest_node(%rax)
    je      3f
    cmp     StoreValidator_latest_epoch(%rax), %r8  # target.epoch > latest_messages[i].epoch
    jbe     2f
3:  mov     %r8, StoreValidator_latest_epoch(%rax)
    mov     %r9, StoreValidator_latest_node(%rax)
2:  dec     %rcx
    jmp     1b
8:  xor     %eax, %eax
7:  LEAVE 16
6:  mov     %rax, (%r15)
    xor     %eax, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END on_attestation

/*
 * rbx store, rbp attester slashing, r12 state, r13 scratch, r14 result, r15 attestation_1;
 * S7 attestation_2, S8 scratch size. Locals: L out.
 */
SPEC_FUNCTION on_attester_slashing
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    movq    $0, (%r14)
    NEED_SCRATCH %r13, %r12, 7, 9f
    mov     (%r13), %rax
    mov     %rax, S8(%rsp)
    PART    %r15, %rax, %rbp, AttesterSlashing_attestation_1
    PART    %rcx, %rax, %rbp, AttesterSlashing_attestation_2
    mov     %rcx, S7(%rsp)
    lea     IndexedAttestation_data(%r15), %rdi     # assert is_slashable_attestation_data(...)
    lea     IndexedAttestation_data(%rcx), %rsi
    lea     L(%rsp), %rdx
    call    lantern_is_slashable_attestation_data
    cmpq    $0, L(%rsp)
    je      6f
    mov     %r12, %rdi                      # assert is_valid_indexed_attestation(state, attestation_1)
    mov     %r15, %rsi
    mov     %r13, %rcx
    lea     L(%rsp), %r8
    mov     (Store_config + CONFIG_PUBKEY_CACHE)(%rbx), %rdx
    call    lantern_is_valid_indexed_attestation
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      7f
    test    %rax, %rax
    jnz     6f
    cmpq    $0, L(%rsp)
    je      6f
    mov     S8(%rsp), %rax                  # and attestation_2
    mov     %rax, (%r13)
    mov     %r12, %rdi
    mov     S7(%rsp), %rsi
    mov     %r13, %rcx
    lea     L(%rsp), %r8
    mov     (Store_config + CONFIG_PUBKEY_CACHE)(%rbx), %rdx
    call    lantern_is_valid_indexed_attestation
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      7f
    test    %rax, %rax
    jnz     6f
    cmpq    $0, L(%rsp)
    je      6f
    PART    %r8, %r9, %rbx, Store_validators        # the common indices: both lists ascend
    PART    %rsi, %rcx, %r15, IndexedAttestation_attesting_indices
    mov     S7(%rsp), %rax
    PART    %rdi, %rdx, %rax, IndexedAttestation_attesting_indices
1:  test    %rcx, %rcx                      # first, every common index needs an entry
    jz      3f
    test    %rdx, %rdx
    jz      3f
    mov     (%rsi), %r10
    mov     (%rdi), %r11
    cmp     %r11, %r10
    jb      11f
    ja      12f
    cmp     %r9, %r10
    jae     9f
    add     $8, %rsi
    dec     %rcx
12: add     $8, %rdi
    dec     %rdx
    jmp     1b
11: add     $8, %rsi
    dec     %rcx
    jmp     1b
3:  PART    %rsi, %rcx, %r15, IndexedAttestation_attesting_indices      # then equivocating_indices.add(index)
    mov     S7(%rsp), %rax
    PART    %rdi, %rdx, %rax, IndexedAttestation_attesting_indices
4:  test    %rcx, %rcx
    jz      8f
    test    %rdx, %rdx
    jz      8f
    mov     (%rsi), %r10
    mov     (%rdi), %r11
    cmp     %r11, %r10
    jb      41f
    ja      42f
    shl     $5, %r10
    orq     $STORE_EQUIVOCATING, StoreValidator_flags(%r8,%r10)
    add     $8, %rsi
    dec     %rcx
42: add     $8, %rdi
    dec     %rdx
    jmp     4b
41: add     $8, %rsi
    dec     %rcx
    jmp     4b
8:  xor     %eax, %eax
7:  LEAVE 16
6:  movq    $LANTERN_INVALID_ATTESTER_SLASHING, (%r14)
    xor     %eax, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END on_attester_slashing

/* ---------------------------------------------------------------- get_proposer_head */

/*
 * rbx store, rbp head node, r12 slot, r13 head state, r14 scratch, r15 out; S7 parent node,
 * S8 the conditions, S9 scratch size, S10 head weight.
 * Locals: L committee count, L+8 index, L+16 epoch, L+24 committee, L+32 reorg threshold.
 * Condition bits: 1 head_late, 2 ffg_competitive, 4 finalization_ok, 8 proposing_on_time,
 * 16 single_slot_reorg, 32 head_weak, 64 parent_strong, 128 current_time_ok, 256 proposer_equivocation.
 */
SPEC_FUNCTION get_proposer_head
    ENTER 48
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     (%rdx), %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r9, %r15
    NEED_BALANCES %rbx, 4f
    NEED_SCRATCH %r14, %r13, 3, 9f
    mov     (%r14), %rax
    mov     %rax, S9(%rsp)
    NODE    %rsi, %rbx, %rbp                # head_block
    mov     BlockNode_parent(%rsi), %rax    # parent_block = store.blocks[parent_root]
    cmp     $-1, %rax
    je      8f
    mov     %rax, S7(%rsp)
    NODE    %rdi, %rbx, %rax
    xor     %ecx, %ecx
    cmpq    $0, BlockNode_timely(%rsi)      # head_late = is_head_late(store, head_node.root)
    sete    %cl
    lea     BlockNode_unrealized_justified_checkpoint(%rsi), %r8   # ffg_competitive
    lea     BlockNode_unrealized_justified_checkpoint(%rdi), %r9
    NE40    %r8, %r9, 1f
    or      $2, %rcx
1:  mov     %r12, %rax                      # finalization_ok = is_finalization_ok(store, slot)
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    sub     (Store_finalized_checkpoint + Checkpoint_epoch)(%rbx), %rax
    jb      10f
    cmp     (Store_config + CONFIG_REORG_MAX_EPOCHS_SINCE_FINALIZATION)(%rbx), %rax
    ja      2f
    or      $4, %rcx
2:  mov     %rcx, %r8                       # proposing_on_time: get_time_into_slot_ms(store) <= cutoff
    STORE_SLOT %rbx, 10f
    mulq    (Store_config + CONFIG_SLOT_DURATION_MS)(%rbx)
    add     Store_genesis_time_ms(%rbx), %rax
    mov     Store_time_ms(%rbx), %r9
    sub     %rax, %r9
    mov     (Store_config + CONFIG_PROPOSER_REORG_CUTOFF_BPS)(%rbx), %rax
    mulq    (Store_config + CONFIG_SLOT_DURATION_MS)(%rbx)
    jc      10f
    mov     $BASIS_POINTS, %ecx
    div     %rcx                            # get_proposer_reorg_cutoff_ms()
    mov     %r8, %rcx
    cmp     %rax, %r9
    ja      3f
    or      $8, %rcx
3:  mov     BlockNode_slot(%rdi), %rax      # parent_slot_ok = parent_block.slot + 1 == head_block.slot
    add     $1, %rax
    jc      10f
    mov     BlockNode_slot(%rsi), %rdx
    xor     %r8d, %r8d
    cmp     %rdx, %rax
    sete    %r8b
    add     $1, %rdx                        # current_time_ok = head_block.slot + 1 == slot
    jc      10f
    xor     %r9d, %r9d
    cmp     %r12, %rdx
    sete    %r9b
    mov     %r9, %rax
    shl     $7, %rax
    or      %rax, %rcx
    and     %r9, %r8
    shl     $4, %r8
    or      %r8, %rcx                       # single_slot_reorg
    mov     %rcx, S8(%rsp)
    lea     Store_proposer_boost_root(%rbx), %rax   # assert store.proposer_boost_root != head_node.root
    NE32    %rax, %rsi, 31f
    mov     $LANTERN_INVALID_PROPOSER_BOOST, %eax
    jmp     7f
31: mov     %rbx, %rdi                      # is_head_weak: reorg_threshold
    mov     (Store_config + CONFIG_REORG_HEAD_WEIGHT_THRESHOLD)(%rbx), %rsi
    call    lantern_committee_fraction
    test    %rax, %rax
    jnz     7f
    mov     %rdx, (L + 32)(%rsp)
    mov     %rbx, %rdi                      # head_weight = get_attestation_score(store, head_node, justified_state)
    mov     %rbp, %rsi
    call    lantern_attestation_score
    test    %rax, %rax
    jnz     7f
    mov     %rdx, S10(%rsp)
    NODE    %rax, %rbx, %rbp
    mov     BlockNode_slot(%rax), %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     %rax, (L + 16)(%rsp)
    mov     %r13, %rdi                      # get_committee_count_per_slot(head_state, epoch)
    lea     (L + 16)(%rsp), %rsi
    mov     %r14, %rcx
    lea     L(%rsp), %r8
    mov     (Store_config + CONFIG_COMMITTEE_CACHE)(%rbx), %rdx
    call    lantern_get_committee_count_per_slot
    test    %rax, %rax
    jnz     7f
    movq    $0, (L + 8)(%rsp)
5:  mov     (L + 8)(%rsp), %rax
    cmp     L(%rsp), %rax
    jae     6f
    mov     (BeaconState_validators + 8)(%r13), %rcx
    mov     S9(%rsp), %rdx
    SCRATCH_LIST %rax, %r14, %rdx, 0, %rcx  # the committee, at the end of scratch
    mov     %rax, (L + 24)(%rsp)
    SCRATCH_GIVE %r14, %rdx, 1, %rcx
    mov     %r13, %rdi                      # get_beacon_committee(head_state, head_block.slot, index)
    NODE    %rsi, %rbx, %rbp
    add     $BlockNode_slot, %rsi
    lea     (L + 8)(%rsp), %rdx
    mov     %r14, %r8
    mov     (L + 24)(%rsp), %r9
    mov     (Store_config + CONFIG_COMMITTEE_CACHE)(%rbx), %rcx
    call    lantern_get_beacon_committee
    test    %rax, %rax
    jnz     7f
    mov     (L + 24)(%rsp), %rax
    mov     LIST_COUNT(%rax), %rcx
    lea     LIST_FIXED(%rax), %rsi
    PART    %rdi, %rdx, %rbx, Store_validators
    mov     S10(%rsp), %r9
51: test    %rcx, %rcx                      # the equivocating members' effective balances
    jz      52f
    mov     (%rsi), %rax
    add     $8, %rsi
    dec     %rcx
    cmp     %rdx, %rax
    jae     51b
    shl     $5, %rax
    add     %rdi, %rax
    mov     StoreValidator_flags(%rax), %r8
    test    $STORE_EQUIVOCATING, %r8
    jz      51b
    test    $STORE_IN_REGISTRY, %r8         # justified_state.validators[index] exists
    jz      11f
    add     StoreValidator_effective_balance(%rax), %r9
    jc      10f
    jmp     51b
52: mov     %r9, S10(%rsp)
    incq    (L + 8)(%rsp)
    jmp     5b
6:  mov     S10(%rsp), %rax                 # head_weak = head_weight < reorg_threshold
    cmp     (L + 32)(%rsp), %rax
    jae     61f
    orq     $32, S8(%rsp)
61: mov     %rbx, %rdi                      # is_parent_strong
    mov     (Store_config + CONFIG_REORG_PARENT_WEIGHT_THRESHOLD)(%rbx), %rsi
    call    lantern_committee_fraction
    test    %rax, %rax
    jnz     7f
    mov     %rdx, S10(%rsp)
    mov     %rbx, %rdi
    mov     S7(%rsp), %rsi
    call    lantern_attestation_score
    test    %rax, %rax
    jnz     7f
    cmp     S10(%rsp), %rdx
    jbe     62f
    orq     $64, S8(%rsp)
62: NODE    %rax, %rbx, %rbp                # is_proposer_equivocation
    mov     BlockNode_proposer_index(%rax), %rcx
    mov     BlockNode_slot(%rax), %rdx
    PART    %rsi, %rdi, %rbx, Store_blocks
    xor     %r8d, %r8d
63: test    %rdi, %rdi
    jz      64f
    cmp     BlockNode_proposer_index(%rsi), %rcx
    jne     631f
    cmp     BlockNode_slot(%rsi), %rdx
    jne     631f
    inc     %r8
631: add    $BlockNode__mem, %rsi
    dec     %rdi
    jmp     63b
64: cmp     $1, %r8
    jbe     65f
    orq     $256, S8(%rsp)
65:
.if FORK >= FORK_FULU
    orq     $512, S8(%rsp)                  # fulu drops the shuffling_stable condition
.else
    test    $(SLOTS_PER_EPOCH - 1), %r12    # shuffling_stable = is_shuffling_stable(slot): slot % SLOTS_PER_EPOCH != 0
    jz      651f
    orq     $512, S8(%rsp)
651:
.endif
    mov     S8(%rsp), %rax
    mov     %rax, %rcx
    and     $(1 | 2 | 4 | 8 | 16 | 32 | 64 | 512), %rcx
    cmp     $(1 | 2 | 4 | 8 | 16 | 32 | 64 | 512), %rcx
    je      66f
    and     $(32 | 128 | 256), %rax         # head_weak, current_time_ok and proposer_equivocation
    cmp     $(32 | 128 | 256), %rax
    je      66f
    mov     %rbp, (%r15)
    jmp     67f
66: mov     S7(%rsp), %rax                  # the parent node
    mov     %rax, (%r15)
67: xor     %eax, %eax
7:  LEAVE 48
4:  mov     $LANTERN_NEED_JUSTIFIED_STATE, %eax
    LEAVE 48
8:  mov     $LANTERN_INVALID_UNKNOWN_BLOCK, %eax
    LEAVE 48
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
10: mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 48
11: mov     $LANTERN_INVALID_VALIDATOR_INDEX, %eax
    LEAVE 48
SPEC_END get_proposer_head

/* ---------------------------------------------------------------- The merge block */

.if FORK == FORK_BELLATRIX
/* L0: rax = 1 when the Uint256 at rdi is below the one at rsi, else 0. A leaf. */
LOCAL_FUNCTION lantern_u256_lo
    UNWIND_END_PROLOGUE
    mov     $24, %ecx                       # from the most significant u64 down
1:  mov     (%rdi,%rcx), %rax
    cmp     (%rsi,%rcx), %rax
    jb      2f
    ja      3f
    sub     $8, %rcx
    jnc     1b
3:  xor     %eax, %eax
    ret
2:  mov     $1, %eax
    ret
END_FUNCTION lantern_u256_lo

/* (block, parent, config, out). Locals: rsp+0 block, parent, config, out; rsp+32 the first condition. */
SPEC_FUNCTION is_valid_terminal_pow_block
    FRAME 48
    mov     %rdi, 0(%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    mov     %rcx, 24(%rsp)
    add     $PowBlock_total_difficulty, %rdi        # is_total_difficulty_reached = block.total_difficulty >= TERMINAL_TOTAL_DIFFICULTY
    lea     CONFIG_TERMINAL_TOTAL_DIFFICULTY(%rdx), %rsi
    call    lantern_u256_lo
    xor     $1, %eax
    mov     %rax, 32(%rsp)
    mov     8(%rsp), %rdi                   # is_parent_total_difficulty_valid = parent.total_difficulty < TERMINAL_TOTAL_DIFFICULTY
    add     $PowBlock_total_difficulty, %rdi
    mov     16(%rsp), %rsi
    add     $CONFIG_TERMINAL_TOTAL_DIFFICULTY, %rsi
    call    lantern_u256_lo
    and     32(%rsp), %rax
    mov     24(%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
    UNFRAME 48
SPEC_END is_valid_terminal_pow_block

/* rbx block, rbp pow_block, r12 pow_parent, r13 config, r14 payload. Locals: L valid. */
SPEC_FUNCTION validate_merge_block
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    PART    %rax, %rcx, %rbx, BeaconBlock_body
    PART    %r14, %rcx, %rax, BeaconBlockBody_execution_payload
    lea     CONFIG_TERMINAL_BLOCK_HASH(%r13), %rsi  # TERMINAL_BLOCK_HASH != Hash32(): the override
    mov     (%rsi), %rax
    or      8(%rsi), %rax
    or      16(%rsi), %rax
    or      24(%rsi), %rax
    jz      1f
    mov     BeaconBlock_slot(%rbx), %rax    # assert compute_epoch_at_slot(block.slot) >= TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    cmp     CONFIG_TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH(%r13), %rax
    jb      6f
    lea     ExecutionPayload_parent_hash(%r14), %rdi    # assert payload.parent_hash == TERMINAL_BLOCK_HASH
    NE32    %rdi, %rsi, 6f
    jmp     8f
1:  test    %rbp, %rbp                      # assert pow_block is not None: get_pow_block(payload.parent_hash)
    jz      6f
    lea     ExecutionPayload_parent_hash(%r14), %rdi
    lea     PowBlock_block_hash(%rbp), %rsi
    NE32    %rdi, %rsi, 6f
    test    %r12, %r12                      # assert pow_parent is not None: get_pow_block(pow_block.parent_hash)
    jz      6f
    lea     PowBlock_parent_hash(%rbp), %rdi
    lea     PowBlock_block_hash(%r12), %rsi
    NE32    %rdi, %rsi, 6f
    mov     %rbp, %rdi                      # assert is_valid_terminal_pow_block(pow_block, pow_parent)
    mov     %r12, %rsi
    mov     %r13, %rdx
    lea     L(%rsp), %rcx
    call    lantern_is_valid_terminal_pow_block
    cmpq    $0, L(%rsp)
    je      6f
8:  xor     %eax, %eax
    LEAVE 16
6:  mov     $LANTERN_INVALID_MERGE_BLOCK, %eax
    LEAVE 16
SPEC_END validate_merge_block
.endif

/* ---------------------------------------------------------------- on_block */

/*
 * rbx store, rbp signed block, r12 state, r13 options, r14 scratch, r15 result; S7 block,
 * S8 scratch size, S9 parent node, S10 dependent slot, then the new node.
 * Locals: L block root (32), L+32 transition options (24, then L+48 the head), L+56 current slot,
 * L+64 pulled up justified (40), L+104 pulled up finalized (40), L+144 saved justification bits,
 * L+152 saved previous justified (40), L+192 saved current justified (40), L+232 saved finalized (40),
 * L+272 its result, L+280 timely, L+288 head dependent node, then the boost, L+296 bellatrix: is_merge_transition_block.
 */
SPEC_FUNCTION on_block
    ENTER 304
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r9, %r15
    movq    $0, (%r15)
    PART    %rax, %rcx, %rbp, SignedBeaconBlock_message
    mov     %rax, S7(%rsp)
    mov     (%r14), %rax
    mov     %rax, S8(%rsp)
    ADDRESS %rdi, lantern_type_BeaconBlock  # block_root = hash_tree_root(block)
    mov     S7(%rsp), %rsi
    mov     %r14, %rdx
    lea     L(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    mov     %rbx, %rdi                      # return early if the block is already known
    lea     L(%rsp), %rsi
    call    lantern_find_node
    cmp     $-1, %rax
    jne     8f
    mov     %rbx, %rdi                      # assert block.parent_root in store.block_states
    mov     S7(%rsp), %rsi
    add     $BeaconBlock_parent_root, %rsi
    call    lantern_find_node
    mov     %rax, S9(%rsp)
    cmp     $-1, %rax
    mov     $LANTERN_INVALID_UNKNOWN_BLOCK, %eax
    je      6f
    mov     S9(%rsp), %rcx                  # the parent's payload is not INVALIDATED (optimistic sync)
    NODE    %rcx, %rbx, %rcx
    cmpq    $PAYLOAD_STATUS_INVALIDATED, BlockNode_payload_status(%rcx)
    mov     $LANTERN_INVALID_PARENT_PAYLOAD, %eax
    je      6f
    STORE_SLOT %rbx, 5f                     # assert get_current_slot(store) >= block.slot
    mov     %rax, (L + 56)(%rsp)
    mov     S7(%rsp), %rcx
    mov     BeaconBlock_slot(%rcx), %rcx
    cmp     %rcx, %rax
    mov     $LANTERN_INVALID_FUTURE_SLOT, %eax
    jb      6f
    mov     (Store_finalized_checkpoint + Checkpoint_epoch)(%rbx), %rdx
    mov     %rdx, %rax
    shr     $(64 - LOG2_SLOTS_PER_EPOCH), %rax
    jnz     5f
    mov     %rdx, %rax
    shl     $LOG2_SLOTS_PER_EPOCH, %rax     # assert block.slot > finalized_slot
    cmp     %rax, %rcx
    mov     $LANTERN_INVALID_NOT_FINALIZED, %eax
    jbe     6f
    mov     %rbx, %rdi                      # finalized_checkpoint_block of the parent
    mov     S9(%rsp), %rsi
    call    lantern_checkpoint_block
    test    %rax, %rax
    jnz     6f
    NODE    %rcx, %rbx, %rdx
    lea     (Store_finalized_checkpoint + Checkpoint_root)(%rbx), %rsi
    mov     $LANTERN_INVALID_NOT_FINALIZED, %eax
    NE32    %rcx, %rsi, 6f
.if FORK >= FORK_DENEB
    mov     $LANTERN_INVALID_DATA_UNAVAILABLE, %eax     # assert is_data_available(block_root)
    cmpq    $0, BlockOptions_data_available(%r13)
    je      6f
.endif
    mov     Store_validators(%rbx), %rax    # before the state changes: room for the node
    sub     Store_blocks(%rbx), %rax
    xor     %edx, %edx
    mov     $BlockNode__mem, %ecx
    div     %rcx
    cmp     %rax, (Store_blocks + 8)(%rbx)
    jae     9f
    NEED_BALANCES %rbx, 4f                  # the justified checkpoint state, for get_head
    mov     (Store_blocks + 8)(%rbx), %rax  # scratch for get_head
    lea     LIST_FIXED(,%rax,8), %rax
    MOVQ    %rcx, LANTERN_SCRATCH_FIXED
    add     %rcx, %rax
    cmp     %rax, S8(%rsp)
    jb      9f
.if FORK == FORK_BELLATRIX
    mov     %r12, %rdi                      # is_merge_transition_block(pre_state, block.body), before the state changes
    mov     S7(%rsp), %rax
    PART    %rsi, %rcx, %rax, BeaconBlock_body
    lea     (L + 296)(%rsp), %rdx
    call    lantern_is_merge_transition_block
.endif
    movq    $1, (L + 32)(%rsp)              # state_transition(state, signed_block, validate_result=True)
    xor     %eax, %eax                      # execution_valid: VALID or NOT_VALIDATED
    cmpq    $PAYLOAD_STATUS_INVALIDATED, BlockOptions_payload_status(%r13)
    setne   %al
    mov     %rax, (L + 40)(%rsp)
    mov     BlockOptions_slots_done(%r13), %rax
    mov     %rax, (L + 48)(%rsp)
    mov     %r12, %rdi
    mov     %rbp, %rsi
    lea     (L + 32)(%rsp), %rdx
    lea     Store_config(%rbx), %rcx
    mov     %r14, %r8
    mov     %r15, %r9
    call    lantern_state_transition
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (%r15)
    jne     8f
.if FORK == FORK_BELLATRIX
    cmpq    $0, (L + 296)(%rsp)             # if is_merge_transition_block(pre_state, block.body): validate_merge_block(block)
    je      1f
    mov     S7(%rsp), %rdi
    mov     BlockOptions_pow_block(%r13), %rsi
    mov     BlockOptions_pow_parent(%r13), %rdx
    lea     Store_config(%rbx), %rcx
    call    lantern_validate_merge_block
    test    %rax, %rax
    jnz     6f
1:
.endif
    mov     S8(%rsp), %rax                  # head = get_head(store), before the block is added
    mov     %rax, (%r14)
    mov     %rbx, %rdi
    mov     %r14, %rsi
    call    lantern_head
    test    %rax, %rax
    jnz     6f
    mov     %rdx, (L + 48)(%rsp)
    movzbl  BeaconState_justification_bits(%r12), %eax  # compute_pulled_up_tip: on a copy of the fields it changes
    mov     %rax, (L + 144)(%rsp)
    lea     BeaconState_previous_justified_checkpoint(%r12), %rcx
    lea     (L + 152)(%rsp), %rdx
    COPY40  %rdx, %rcx
    lea     BeaconState_current_justified_checkpoint(%r12), %rcx
    lea     (L + 192)(%rsp), %rdx
    COPY40  %rdx, %rcx
    lea     BeaconState_finalized_checkpoint(%r12), %rcx
    lea     (L + 232)(%rsp), %rdx
    COPY40  %rdx, %rcx
    mov     S8(%rsp), %rax
    mov     %rax, (%r14)
    mov     %r12, %rdi                      # process_justification_and_finalization(state)
    lea     Store_config(%rbx), %rsi
    mov     %r14, %rdx
    lea     (L + 272)(%rsp), %rcx
    call    lantern_process_justification_and_finalization
    mov     %rax, S10(%rsp)
    lea     BeaconState_current_justified_checkpoint(%r12), %rcx
    lea     (L + 64)(%rsp), %rdx
    COPY40  %rdx, %rcx
    lea     BeaconState_finalized_checkpoint(%r12), %rcx
    lea     (L + 104)(%rsp), %rdx
    COPY40  %rdx, %rcx
    mov     (L + 144)(%rsp), %rax           # the post-state again
    mov     %al, BeaconState_justification_bits(%r12)
    lea     BeaconState_previous_justified_checkpoint(%r12), %rdx
    lea     (L + 152)(%rsp), %rcx
    COPY40  %rdx, %rcx
    lea     BeaconState_current_justified_checkpoint(%r12), %rdx
    lea     (L + 192)(%rsp), %rcx
    COPY40  %rdx, %rcx
    lea     BeaconState_finalized_checkpoint(%r12), %rdx
    lea     (L + 232)(%rsp), %rcx
    COPY40  %rdx, %rcx
    mov     S10(%rsp), %rax
    test    %rax, %rax
    jnz     7f
    mov     (L + 272)(%rsp), %rax
    test    %rax, %rax
    jnz     6f
    mov     (L + 56)(%rsp), %rax            # record_block_timeliness
    mulq    (Store_config + CONFIG_SLOT_DURATION_MS)(%rbx)
    add     Store_genesis_time_ms(%rbx), %rax
    mov     Store_time_ms(%rbx), %rcx
    sub     %rax, %rcx                      # time_into_slot_ms
    mov     (Store_config + CONFIG_ATTESTATION_DUE_BPS)(%rbx), %rax
    mulq    (Store_config + CONFIG_SLOT_DURATION_MS)(%rbx)
    jc      5f
    mov     $BASIS_POINTS, %esi
    div     %rsi                            # get_attestation_due_ms()
    xor     %edx, %edx
    cmp     %rax, %rcx
    setb    %dl                             # is_before_attesting_interval
    mov     (L + 56)(%rsp), %rax
    mov     S7(%rsp), %rsi
    cmp     BeaconBlock_slot(%rsi), %rax
    je      40f
    xor     %edx, %edx                      # is_timely
40: mov     %rdx, (L + 280)(%rsp)
    shr     $LOG2_SLOTS_PER_EPOCH, %rax     # update_proposer_boost_root: the dependent slot of the current epoch
    xor     %ecx, %ecx
    sub     $MIN_SEED_LOOKAHEAD, %rax
    cmovb   %rcx, %rax
    shl     $LOG2_SLOTS_PER_EPOCH, %rax
    sub     $1, %rax
    cmovb   %rcx, %rax
    mov     %rax, S10(%rsp)
    mov     %rbx, %rdi                      # head_dependent_root
    mov     (L + 48)(%rsp), %rsi
    mov     %rax, %rdx
    call    lantern_ancestor
    test    %rax, %rax
    jnz     6f
    mov     %rdx, (L + 288)(%rsp)
    mov     (Store_blocks + 8)(%rbx), %rcx  # block_dependent_root: the new node, or an ancestor of its parent
    mov     S7(%rsp), %rax
    mov     BeaconBlock_slot(%rax), %rax
    cmp     S10(%rsp), %rax
    jbe     41f
    mov     %rbx, %rdi
    mov     S9(%rsp), %rsi
    mov     S10(%rsp), %rdx
    call    lantern_ancestor
    test    %rax, %rax
    jnz     6f
    mov     %rdx, %rcx
41: xor     %eax, %eax
    cmp     (L + 288)(%rsp), %rcx
    sete    %al                             # is_same_dependent_root
    and     (L + 280)(%rsp), %rax
    mov     Store_proposer_boost_root(%rbx), %rcx   # is_first_block
    or      (Store_proposer_boost_root + 8)(%rbx), %rcx
    or      (Store_proposer_boost_root + 16)(%rbx), %rcx
    or      (Store_proposer_boost_root + 24)(%rbx), %rcx
    jz      43f
    xor     %eax, %eax
43: mov     %rax, (L + 288)(%rsp)
    mov     (Store_blocks + 8)(%rbx), %rax  # every check holds: the writes, in spec order
    lea     1(%rax), %rcx
    mov     %rcx, (Store_blocks + 8)(%rbx)
    NODE    %rax, %rbx, %rax                # store.blocks[block_root] = block
    lea     L(%rsp), %rcx
    COPY32  %rax, %rcx
    mov     S7(%rsp), %rsi
    lea     BlockNode_parent_root(%rax), %rdx
    lea     BeaconBlock_parent_root(%rsi), %rcx
    COPY32  %rdx, %rcx
    mov     BeaconBlock_slot(%rsi), %rcx
    mov     %rcx, BlockNode_slot(%rax)
    mov     BeaconBlock_proposer_index(%rsi), %rcx
    mov     %rcx, BlockNode_proposer_index(%rax)
    mov     S9(%rsp), %rcx
    mov     %rcx, BlockNode_parent(%rax)
    lea     BlockNode_justified_checkpoint(%rax), %rdx  # block_states[block_root].current_justified_checkpoint
    lea     BeaconState_current_justified_checkpoint(%r12), %rcx
    COPY40  %rdx, %rcx
    mov     (BeaconState_finalized_checkpoint + Checkpoint_epoch)(%r12), %rcx   # and its finalized_checkpoint.epoch
    mov     %rcx, BlockNode_finalized_epoch(%rax)
    lea     BlockNode_unrealized_justified_checkpoint(%rax), %rdx      # unrealized_justifications[block_root]
    lea     (L + 64)(%rsp), %rcx
    COPY40  %rdx, %rcx
    mov     (L + 280)(%rsp), %rcx           # block_timeliness[block_root]
    mov     %rcx, BlockNode_timely(%rax)
.if FORK >= FORK_BELLATRIX
    PART    %rdx, %rcx, %rsi, BeaconBlock_body      # the payload's hash and status
    PART    %rdi, %rcx, %rdx, BeaconBlockBody_execution_payload
    add     $ExecutionPayload_block_hash, %rdi
    lea     BlockNode_block_hash(%rax), %rdx
    COPY32  %rdx, %rdi
.else
    .irp k, 0, 8, 16, 24
    movq    $0, (BlockNode_block_hash + \k)(%rax)  # no payload before bellatrix: a zero hash
    .endr
.endif
    mov     BlockOptions_payload_status(%r13), %rcx
    mov     %rcx, BlockNode_payload_status(%rax)
    test    %rcx, %rcx
    jnz     92f                             # VALID: so are its NOT_VALIDATED ancestors
    mov     S9(%rsp), %rcx
91: cmp     $-1, %rcx
    je      92f
    NODE    %rdx, %rbx, %rcx
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, BlockNode_payload_status(%rdx)
    jne     92f
    movq    $PAYLOAD_STATUS_VALID, BlockNode_payload_status(%rdx)
    mov     BlockNode_parent(%rdx), %rcx
    jmp     91b
92:
    cmpq    $0, (L + 288)(%rsp)             # proposer_boost_root = block_root
    je      42f
    lea     Store_proposer_boost_root(%rbx), %rdx
    lea     L(%rsp), %rcx
    COPY32  %rdx, %rcx
42: mov     %rbx, %rdi                      # lantern_update_checkpoints(store, state.current_justified, state.finalized)
    lea     BeaconState_current_justified_checkpoint(%r12), %rsi
    lea     BeaconState_finalized_checkpoint(%r12), %rdx
    call    lantern_update_checkpoints
    mov     %rbx, %rdi                      # compute_pulled_up_tip
    lea     (L + 64)(%rsp), %rsi
    lea     (L + 104)(%rsp), %rdx
    call    lantern_update_unrealized_checkpoints
    mov     S7(%rsp), %rax
    mov     BeaconBlock_slot(%rax), %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     (L + 56)(%rsp), %rcx
    shr     $LOG2_SLOTS_PER_EPOCH, %rcx
    cmp     %rcx, %rax                      # a block from a prior epoch: the realized values
    jae     8f
    mov     %rbx, %rdi
    lea     (L + 64)(%rsp), %rsi
    lea     (L + 104)(%rsp), %rdx
    call    lantern_update_checkpoints
8:  xor     %eax, %eax
7:  LEAVE 304
6:  mov     %rax, (%r15)
    xor     %eax, %eax
    LEAVE 304
5:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    jmp     6b
4:  mov     $LANTERN_NEED_JUSTIFIED_STATE, %eax
    LEAVE 304
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 304
SPEC_END on_block

/* ---------------------------------------------------------------- Data availability */

.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
/*
 * (blob_kzg_commitments, blobs, proofs, settings, scratch, out): verify_blob_kzg_proof_batch of the blobs
 * and proofs that retrieve_blobs_and_proofs gave. Locals: rsp+0 out.
 */
SPEC_FUNCTION is_data_available
    FRAME 16
    mov     %r9, 0(%rsp)
    mov     %rdi, %rax                      # asm-crypto: settings, blobs, commitments, proofs, scratch, valid
    mov     %rcx, %rdi
    mov     %rdx, %rcx
    mov     %rax, %rdx
    CALL_GLOBAL crypto_kzg_verify_blob_kzg_proof_batch
    cmp     $CRYPTO_BUFFER_TOO_SMALL, %rax
    je      9f
    test    %rax, %rax
    jz      8f
    mov     0(%rsp), %rcx                   # a KZG input that fails its checks: the spec's exception, not available
    movq    $0, (%rcx)
8:  xor     %eax, %eax
    UNFRAME 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    UNFRAME 16
SPEC_END is_data_available
.endif

.if FORK >= FORK_FULU

/* Locals: rsp+0 epoch, rsp+8 blob parameters (16), rsp+24 sidecar, rsp+32 out. */
SPEC_FUNCTION verify_data_column_sidecar
    FRAME 48
    mov     %rdi, 24(%rsp)
    mov     %rdx, 32(%rsp)
    movq    $0, (%rdx)
    cmpq    $NUMBER_OF_COLUMNS, DataColumnSidecar_index(%rdi)   # sidecar.index < NUMBER_OF_COLUMNS
    jae     8f
    cmpq    $0, (DataColumnSidecar_kzg_commitments + 8)(%rdi)   # a sidecar for zero blobs is invalid
    je      8f
    mov     (DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(%rdi), %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     %rax, (%rsp)
    mov     %rsp, %rdi                      # get_blob_parameters(epoch).max_blobs_per_block
    lea     8(%rsp), %rdx
    call    lantern_get_blob_parameters
    mov     24(%rsp), %rdi
    mov     (DataColumnSidecar_kzg_commitments + 8)(%rdi), %rax
    cmp     16(%rsp), %rax
    ja      8f
    cmp     (DataColumnSidecar_column + 8)(%rdi), %rax
    jne     8f
    cmp     (DataColumnSidecar_kzg_proofs + 8)(%rdi), %rax
    jne     8f
    mov     32(%rsp), %rdx
    movq    $1, (%rdx)
8:  xor     %eax, %eax
    UNFRAME 48
SPEC_END verify_data_column_sidecar

/* A list of r14 entries of stride bytes at the end of scratch r12, below r15: its address to slot. Uses rax, rcx. */
.macro DA_LIST slot, stride
    imul    $(\stride), %r14, %rax
    add     $LIST_FIXED, %rax
    sub     %rax, %r15
    lea     (%r12,%r15), %rcx
    mov     %rax, LIST_SIZE(%rcx)
    movq    $LIST_FIXED, LIST_OFFSET(%rcx)
    mov     %r14, LIST_COUNT(%rcx)
    mov     %rcx, \slot(%rsp)
.endm

/*
 * rbx sidecar, rbp settings, r12 scratch, r13 out, r14 n, r15 scratch size left;
 * S7 the seventh argument of the KZG call, S8 commitments, S9 cell indices, S10 cells,
 * L proofs, L+8 valid.
 */
SPEC_FUNCTION verify_data_column_sidecar_kzg_proofs
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    movq    $0, (%r13)
    mov     (DataColumnSidecar_kzg_commitments + 8)(%rbx), %r14
    mov     %r14, %rax
    MOVQ    %rcx, DA_SCRATCH_PER_BLOB
    mul     %rcx
    jc      9f
    MOVQ    %rcx, DA_SCRATCH_FIXED
    add     %rcx, %rax
    jc      9f
    mov     (%r12), %r15
    cmp     %rax, %r15
    jb      9f
    DA_LIST S8, 48                          # commitments_bytes = sidecar.kzg_commitments
    DA_LIST S9, 8                           # cell_indices = [sidecar.index] * len(sidecar.column)
    DA_LIST S10, CRYPTO_KZG_CELL_SIZE       # cells = sidecar.column
    DA_LIST L, 48                           # proofs_bytes = sidecar.kzg_proofs
    mov     S8(%rsp), %rdi
    add     $LIST_FIXED, %rdi
    PART    %rsi, %rdx, %rbx, DataColumnSidecar_kzg_commitments
    imul    $48, %rdx, %rdx
    call    lantern_copy
    mov     DataColumnSidecar_index(%rbx), %rax
    mov     S9(%rsp), %rdi
    add     $LIST_FIXED, %rdi
    mov     %r14, %rcx
    rep stosq
    mov     S10(%rsp), %rdi
    add     $LIST_FIXED, %rdi
    PART    %rsi, %rdx, %rbx, DataColumnSidecar_column
    shl     $11, %rdx
    call    lantern_copy
    mov     L(%rsp), %rdi
    add     $LIST_FIXED, %rdi
    PART    %rsi, %rdx, %rbx, DataColumnSidecar_kzg_proofs
    imul    $48, %rdx, %rdx
    call    lantern_copy
    mov     %r15, (%r12)                    # asm-crypto's scratch: the front
    mov     %rbp, %rdi
    mov     S8(%rsp), %rsi
    mov     S9(%rsp), %rdx
    mov     S10(%rsp), %rcx
    mov     L(%rsp), %r8
    mov     %r12, %r9
    lea     (L + 8)(%rsp), %rax             # valid, the seventh argument, on the stack
    mov     %rax, S7(%rsp)
    CALL_GLOBAL crypto_kzg_verify_cell_kzg_proof_batch
    cmp     $CRYPTO_BUFFER_TOO_SMALL, %rax
    je      9f
    test    %rax, %rax
    jnz     8f                              # an input that does not decode: the spec raises
    mov     (L + 8)(%rsp), %rax
    mov     %rax, (%r13)
8:  xor     %eax, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END verify_data_column_sidecar_kzg_proofs

/* rbx sidecar, rbp settings, r12 config, r13 scratch, r14 out, r15 sidecars left; S7 scratch size. */
SPEC_FUNCTION is_data_available
    ENTER 16
    PART    %rbx, %r15, %rdi, 8             # a standalone list: its PartRef at 8
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     (%r13), %rax
    mov     %rax, S7(%rsp)
    movq    $1, (%r14)                      # all([]) is True
1:  test    %r15, %r15
    jz      8f
    mov     %rbx, %rdi                      # verify_data_column_sidecar(column_sidecar)
    mov     %r12, %rsi
    mov     %r14, %rdx
    call    lantern_verify_data_column_sidecar
    cmpq    $0, (%r14)
    je      8f
    mov     S7(%rsp), %rax                  # and verify_data_column_sidecar_kzg_proofs(column_sidecar)
    mov     %rax, (%r13)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r13, %rdx
    mov     %r14, %rcx
    call    lantern_verify_data_column_sidecar_kzg_proofs
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (%r14)
    je      8f
    add     (%rbx), %rbx
    dec     %r15
    jmp     1b
8:  xor     %eax, %eax
7:  LEAVE 16
SPEC_END is_data_available
.endif
