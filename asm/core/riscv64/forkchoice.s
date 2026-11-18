/*
 * Fork choice, RISC-V. Requirements: docs/reference/fork-choice.md.
 * A ForkChoiceNode is the index of its BlockNode in the store.
 */

.set FC_ATTEST_EXTRA, IndexedAttestation__fixed + 8 + CIDX_BYTES

/* get_head: the flags of each node, a u64 each at the end of scratch. */
.set F_SUBTREE, 1          # in the subtree of the justified node
.set F_CHILD, 2            # has a child
.set F_VIABLE, 4           # in get_filtered_node_tree
.set F_CHILD_VIABLE, 8     # has a child in get_filtered_node_tree

.if BlockNode__mem != 216 || StoreValidator__mem != 32 || Checkpoint__mem != 40 || Checkpoint_root != 8
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

/* dst = the address of node idx of store st. Uses a6, a7. */
.macro NODE dst, st, idx
    ld      a6, Store_blocks(\st)
    add     a6, \st, a6
    li      a7, BlockNode__mem
    mul     a7, \idx, a7
    add     \dst, a6, a7
.endm

/* dst = get_current_slot(store st); branch to fail when time_ms is before genesis_time_ms. Uses a6. */
.macro STORE_SLOT dst, st, fail
    ld      \dst, Store_time_ms(\st)
    ld      a6, Store_genesis_time_ms(\st)
    bltu    \dst, a6, \fail
    sub     \dst, \dst, a6
    ld      a6, (Store_config + CONFIG_SLOT_DURATION_MS)(\st)
    divu    \dst, \dst, a6
.endm

/* The 40-byte Checkpoint at dst = the one at src. Uses a6, a7. */
.macro COPY40 dst, src
    COPY32  \dst, \src
    ld      a6, 32(\src)
    sd      a6, 32(\dst)
.endm

/* Branch to label when the Checkpoints at a and at b differ. Uses a6, a7. */
.macro NE40 a, b, label
    NE32    \a, \b, \label
    ld      a6, 32(\a)
    ld      a7, 32(\b)
    bne     a6, a7, \label
.endm

/* Branch to fail when the balances of store st are not those of its justified checkpoint. Uses t5, t6, a6, a7. */
.macro NEED_BALANCES st, fail
    addi    t5, \st, Store_balances_checkpoint
    addi    t6, \st, Store_justified_checkpoint
    NE40    t5, t6, \fail
.endm

/* The Checkpoint at dst = the one at src when src's epoch is greater (update_checkpoints). Uses a6, a7. */
.macro RAISE dst, src
    ld      a6, Checkpoint_epoch(\src)
    ld      a7, Checkpoint_epoch(\dst)
    bgeu    a7, a6, 98f
    COPY40  \dst, \src
98:
.endm

/* Branch to gt when the root at a is greater than the root at b as a byte string, else to le. Uses i, a6, a7. */
.macro ROOT_GT a, b, gt, le, i
    li      \i, 0
97: add     a6, \a, \i
    lbu     a6, 0(a6)
    add     a7, \b, \i
    lbu     a7, 0(a7)
    bltu    a7, a6, \gt
    bltu    a6, a7, \le
    addi    \i, \i, 1
    li      a6, 32
    bltu    \i, a6, 97b
    j       \le
.endm

/* dst = 1 when validator v is active at epoch and not slashed, else 0. Uses a6. */
.macro ACTIVE_UNSLASHED dst, v, epoch
    li      \dst, 0
    ld      a6, Validator_activation_epoch(\v)
    bltu    \epoch, a6, 96f                 # activation_epoch <= epoch
    ld      a6, Validator_exit_epoch(\v)
    bgeu    \epoch, a6, 96f                 # epoch < exit_epoch
    lbu     a6, Validator_slashed(\v)
    bnez    a6, 96f
    li      \dst, 1
96:
.endm

/* ---------------------------------------------------------------- Nodes */

/* L0: a0 = the node of the root at a1 in store a0, or NODE_NONE. A leaf; uses a2-a5, t0-t4, a7. */
LOCAL_FUNCTION find_node
    UNWIND_END_PROLOGUE
    PART    a2, a3, a0, Store_blocks
    ld      a4, 0(a1)
    ld      a5, 8(a1)
    ld      t0, 16(a1)
    ld      t1, 24(a1)
    li      t2, BlockNode__mem
1:  beqz    a3, 9f                          # newest first
    addi    a3, a3, -1
    mul     t3, a3, t2
    add     t3, a2, t3
    ld      t4, 0(t3)
    bne     t4, a4, 1b
    ld      t4, 8(t3)
    bne     t4, a5, 1b
    ld      t4, 16(t3)
    bne     t4, t0, 1b
    ld      t4, 24(t3)
    bne     t4, t1, 1b
    mv      a0, a3
    ret
9:  li      a0, -1                          # NODE_NONE
    ret
END_FUNCTION find_node

/* L0: a0 = status, a1 = get_ancestor(store a0, node a1, slot a2). A leaf; uses a3-a5, t0, t1. */
LOCAL_FUNCTION ancestor
    UNWIND_END_PROLOGUE
    ld      a3, Store_blocks(a0)
    add     a3, a0, a3
    li      a4, BlockNode__mem
    li      t0, -1
1:  mul     a5, a1, a4
    add     a5, a3, a5
    ld      t1, BlockNode_slot(a5)
    bgeu    a2, t1, 2f
    ld      a1, BlockNode_parent(a5)        # the parent, when it is in the store
    bne     a1, t0, 1b
    li      a0, LANTERN_INVALID_UNKNOWN_BLOCK
    ret
2:  li      a0, LANTERN_OK
    ret
END_FUNCTION ancestor

/* L0: a0 = status, a1 = the node of get_checkpoint_block(store a0, node a1, epoch a2). A leaf. */
LOCAL_FUNCTION checkpoint_block
    UNWIND_END_PROLOGUE
    srli    a3, a2, (64 - LOG2_SLOTS_PER_EPOCH)     # compute_start_slot_at_epoch(epoch) fits
    bnez    a3, 9f
    slli    a2, a2, LOG2_SLOTS_PER_EPOCH
    j       ancestor
9:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION checkpoint_block

SPEC_LEAF get_current_slot
    STORE_SLOT a2, a0, 9f
    sd      a2, 0(a1)
    RETURN_OK
9:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
SPEC_END get_current_slot

SPEC_LEAF get_current_store_epoch
    STORE_SLOT a2, a0, 9f
    srli    a2, a2, LOG2_SLOTS_PER_EPOCH
    sd      a2, 0(a1)
    RETURN_OK
9:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
SPEC_END get_current_store_epoch

SPEC_FUNCTION get_ancestor
    FRAME 16
    sd      a3, F(sp)
    ld      a1, 0(a1)
    ld      a2, 0(a2)
    call    ancestor
    bnez    a0, 1f
    ld      a3, F(sp)
    sd      a1, 0(a3)
1:  UNFRAME 16
SPEC_END get_ancestor

/* Locals: F store, F+8 out, F+16 epoch. */
SPEC_FUNCTION get_checkpoint_block
    FRAME 32
    sd      a0, F(sp)
    sd      a3, (F + 8)(sp)
    ld      a2, 0(a2)
    sd      a2, (F + 16)(sp)
    call    find_node
    li      t0, -1
    beq     a0, t0, 8f
    mv      a1, a0
    ld      a0, F(sp)
    ld      a2, (F + 16)(sp)
    call    checkpoint_block
    bnez    a0, 7f
    ld      a0, F(sp)
    ld      a3, (F + 8)(sp)
    NODE    a1, a0, a1
    COPY32  a3, a1
    li      a0, LANTERN_OK
7:  UNFRAME 32
8:  li      a0, LANTERN_INVALID_UNKNOWN_BLOCK
    UNFRAME 32
SPEC_END get_checkpoint_block

/* ---------------------------------------------------------------- Weights */

/*
 * L0: a0 = status, a1 = get_attestation_score(store a0, node a1) with the store's balances.
 * A leaf; uses a2-a5, t0-t6. An overflow is reported after the sum, as the spec's Gwei does.
 */
LOCAL_FUNCTION attestation_score
    UNWIND_END_PROLOGUE
    ld      a2, Store_blocks(a0)
    add     a2, a0, a2                      # the nodes
    li      a3, BlockNode__mem
    mul     a4, a1, a3
    add     a4, a2, a4
    ld      a4, BlockNode_slot(a4)          # store.blocks[node.root].slot
    PART    a5, t0, a0, Store_validators
    li      t1, 0                           # the sum
    li      t2, 0                           # carries
1:  beqz    t0, 5f
    addi    t0, t0, -1
    ld      t3, StoreValidator_flags(a5)
    andi    t3, t3, (STORE_ACTIVE_UNSLASHED | STORE_EQUIVOCATING)
    li      t4, STORE_ACTIVE_UNSLASHED      # unslashed and active, not equivocating
    bne     t3, t4, 4f
    ld      t3, StoreValidator_latest_node(a5)
    li      t4, -1                          # index in store.latest_messages
    beq     t3, t4, 4f
    mul     t5, t3, a3                      # not a vote for an INVALIDATED block (optimistic sync)
    add     t5, a2, t5
    ld      t6, BlockNode_payload_status(t5)
    li      t5, PAYLOAD_STATUS_INVALIDATED
    beq     t6, t5, 4f
2:  mul     t5, t3, a3                      # is_ancestor(latest message node, node)
    add     t5, a2, t5
    ld      t6, BlockNode_slot(t5)
    bgeu    a4, t6, 3f
    ld      t3, BlockNode_parent(t5)
    bne     t3, t4, 2b
    li      a0, LANTERN_INVALID_UNKNOWN_BLOCK
    ret
3:  bne     t3, a1, 4f
    ld      t5, StoreValidator_effective_balance(a5)
    add     t6, t1, t5
    sltu    t5, t6, t1
    or      t2, t2, t5
    mv      t1, t6
4:  addi    a5, a5, StoreValidator__mem
    j       1b
5:  bnez    t2, 9f
    mv      a1, t1
    li      a0, LANTERN_OK
    ret
9:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION attestation_score

/*
 * L0: a0 = status, a1 = calculate_committee_fraction(justified state, percent a1), from the
 * store's total balance. A leaf; uses a2, a3.
 */
LOCAL_FUNCTION committee_fraction
    UNWIND_END_PROLOGUE
    ld      a2, Store_balances_total(a0)
    srli    a2, a2, LOG2_SLOTS_PER_EPOCH    # committee_weight = total_balance // SLOTS_PER_EPOCH
    mulhu   a3, a2, a1
    bnez    a3, 9f
    mul     a2, a2, a1
    li      a3, 100
    divu    a1, a2, a3
    li      a0, LANTERN_OK
    ret
9:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION committee_fraction

/* L0: a0 = status, a1 = get_weight(store a0, node a1) with the store's balances. s1 store, s2 node, s3 score. */
LOCAL_FUNCTION weight
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    call    attestation_score
    bnez    a0, 7f
    mv      s3, a1
    addi    a1, s1, Store_proposer_boost_root
    ld      t0, 0(a1)
    ld      t1, 8(a1)
    ld      t2, 16(a1)
    ld      t3, 24(a1)
    or      t0, t0, t1
    or      t2, t2, t3
    or      t0, t0, t2
    beqz    t0, 6f                          # no proposer_boost_root: the attestation score
    mv      a0, s1
    call    find_node
    li      t0, -1
    beq     a0, t0, 8f
    NODE    t0, s1, a0                      # no boost from an INVALIDATED block (optimistic sync)
    ld      t0, BlockNode_payload_status(t0)
    li      t1, PAYLOAD_STATUS_INVALIDATED
    beq     t0, t1, 6f
    mv      a1, a0                          # is_ancestor(store, proposer_boost_node, node)
    NODE    t0, s1, s2
    ld      a2, BlockNode_slot(t0)
    mv      a0, s1
    call    ancestor
    bnez    a0, 7f
    bne     a1, s2, 6f
    mv      a0, s1                          # get_proposer_score(store)
    ld      a1, (Store_config + CONFIG_PROPOSER_SCORE_BOOST)(s1)
    call    committee_fraction
    bnez    a0, 7f
    add     t0, s3, a1
    bltu    t0, s3, 9f
    mv      s3, t0
6:  mv      a1, s3
    li      a0, LANTERN_OK
7:  LEAVE 0
8:  li      a0, LANTERN_INVALID_UNKNOWN_BLOCK
    LEAVE 0
9:  li      a0, LANTERN_INVALID_OVERFLOW
    LEAVE 0
END_FUNCTION weight

SPEC_FUNCTION get_weight
    FRAME 16
    sd      a2, F(sp)
    NEED_BALANCES a0, 8f
    ld      a1, 0(a1)
    call    weight
    bnez    a0, 7f
    ld      a2, F(sp)
    sd      a1, 0(a2)
7:  UNFRAME 16
8:  li      a0, LANTERN_NEED_JUSTIFIED_STATE
    UNFRAME 16
SPEC_END get_weight

/* ---------------------------------------------------------------- get_head */

/*
 * L0: get_filtered_node_tree(store a0), with scratch a1 of S(1) for the node count: a0 = status,
 * a1 = the flags of each node at the end of scratch (F_VIABLE: in the tree), a2 = the justified node.
 * s1 store, s2 flags, s3 node count, s4 justified node, s5 current epoch, s6 i,
 * s8 correct_justified, s10 nodes.
 */
LOCAL_FUNCTION filter_tree
    ENTER 16
    mv      s1, a0
    ld      s3, (Store_blocks + 8)(s1)
    ld      t0, 0(a1)                       # scratch: the flags at its end
    slli    t1, s3, 3
    addi    t2, t1, LIST_FIXED
    li      t3, LANTERN_SCRATCH_FIXED
    add     t2, t2, t3
    bltu    t0, t2, 9f
    sub     t0, t0, t1
    add     s2, a1, t0
    ld      s10, Store_blocks(s1)
    add     s10, s1, s10
    mv      a0, s1
    addi    a1, s1, (Store_justified_checkpoint + Checkpoint_root)
    call    find_node
    li      t0, -1
    beq     a0, t0, 8f
    mv      s4, a0
    STORE_SLOT s5, s1, 10f
    srli    s5, s5, LOG2_SLOTS_PER_EPOCH    # get_current_store_epoch(store)
    mv      a0, s2
    slli    a1, s3, 3
    call    lantern_zero
    li      t0, F_SUBTREE                   # the subtree of the justified node: parents come first
    slli    t1, s4, 3
    add     t1, s2, t1
    sd      t0, 0(t1)
    addi    s6, s4, 1
    li      t6, BlockNode__mem
1:  bgeu    s6, s3, 2f
    mul     t1, s6, t6
    add     t1, s10, t1
    ld      t2, BlockNode_parent(t1)
    li      t0, -1
    beq     t2, t0, 15f
    ld      t3, BlockNode_payload_status(t1)
    li      t0, PAYLOAD_STATUS_INVALIDATED  # removed from fork choice (optimistic sync)
    beq     t3, t0, 15f
    slli    t2, t2, 3
    add     t2, s2, t2
    ld      t3, 0(t2)
    andi    t0, t3, F_SUBTREE
    beqz    t0, 15f
    ori     t3, t3, F_CHILD
    sd      t3, 0(t2)
    slli    t1, s6, 3
    add     t1, s2, t1
    li      t0, F_SUBTREE
    sd      t0, 0(t1)
15: addi    s6, s6, 1
    j       1b
2:  addi    s6, s3, -1                      # filter_node_tree: children come before their parent
3:  blt     s6, s4, 6f
    slli    t1, s6, 3
    add     t1, s2, t1
    ld      t3, 0(t1)
    andi    t0, t3, F_SUBTREE
    beqz    t0, 5f
    andi    t0, t3, F_CHILD
    beqz    t0, 31f
    andi    t0, t3, F_CHILD_VIABLE          # with children: viable when a child is
    beqz    t0, 5f
    j       4f
31: li      t0, BlockNode__mem              # a leaf
    mul     t4, s6, t0
    add     t4, s10, t4
    ld      t1, BlockNode_slot(t4)          # voting_source = get_voting_source(store, node.root)
    srli    t1, t1, LOG2_SLOTS_PER_EPOCH
    addi    t5, t4, BlockNode_justified_checkpoint
    bgeu    t1, s5, 32f                     # current_epoch > block_epoch: the pulled up source
    addi    t5, t4, BlockNode_unrealized_justified_checkpoint
32: ld      t5, Checkpoint_epoch(t5)
    li      s8, 1                           # correct_justified
    ld      t6, (Store_justified_checkpoint + Checkpoint_epoch)(s1)
    beqz    t6, 34f                         # store.justified_checkpoint.epoch == GENESIS_EPOCH
    beq     t5, t6, 34f
    addi    t6, t5, 2                       # voting_source.epoch + 2 >= current_epoch
    bltu    t6, t5, 10f
    bgeu    t6, s5, 34f
    li      s8, 0
34: mv      a0, s1                          # finalized_checkpoint_block
    mv      a1, s6
    ld      a2, (Store_finalized_checkpoint + Checkpoint_epoch)(s1)
    call    checkpoint_block
    bnez    a0, 7f
    ld      t0, (Store_finalized_checkpoint + Checkpoint_epoch)(s1)
    beqz    t0, 35f                         # correct_finalized
    NODE    t5, s1, a1
    addi    t6, s1, (Store_finalized_checkpoint + Checkpoint_root)
    NE32    t5, t6, 5f
35: beqz    s8, 5f
4:  slli    t1, s6, 3                       # viable: so is its parent
    add     t1, s2, t1
    ld      t3, 0(t1)
    ori     t3, t3, F_VIABLE
    sd      t3, 0(t1)
    beq     s6, s4, 5f
    li      t0, BlockNode__mem
    mul     t4, s6, t0
    add     t4, s10, t4
    ld      t2, BlockNode_parent(t4)
    slli    t2, t2, 3
    add     t2, s2, t2
    ld      t3, 0(t2)
    ori     t3, t3, F_CHILD_VIABLE
    sd      t3, 0(t2)
5:  addi    s6, s6, -1
    j       3b
6:  mv      a1, s2
    mv      a2, s4
    li      a0, LANTERN_OK
7:  LEAVE 16
8:  li      a0, LANTERN_INVALID_UNKNOWN_BLOCK
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
10: li      a0, LANTERN_INVALID_OVERFLOW
    LEAVE 16
END_FUNCTION filter_tree

/*
 * L0: a0 = status, a1 = get_head(store a0), with scratch a1 of S(1) for the node count.
 * s1 store, s2 flags, s3 node count, s4 justified node, s6 i, s7 head, s8 best child,
 * s9 best weight, s10 nodes.
 */
LOCAL_FUNCTION head
    ENTER 16
    mv      s1, a0
    call    filter_tree                     # nodes = get_filtered_node_tree(store)
    bnez    a0, 7f
    mv      s2, a1
    mv      s4, a2
    ld      s3, (Store_blocks + 8)(s1)
    ld      s10, Store_blocks(s1)
    add     s10, s1, s10
60: mv      s7, s4                          # head = the justified node
61: li      s8, -1                          # the best child so far
    li      s9, 0
    addi    s6, s7, 1
62: bgeu    s6, s3, 65f
    li      t0, BlockNode__mem
    mul     t4, s6, t0
    add     t4, s10, t4
    ld      t2, BlockNode_parent(t4)
    bne     t2, s7, 64f
    slli    t1, s6, 3
    add     t1, s2, t1
    ld      t3, 0(t1)
    andi    t3, t3, F_VIABLE                # a child in nodes
    beqz    t3, 64f
    mv      a0, s1
    mv      a1, s6
    call    weight
    bnez    a0, 7f
    li      t0, -1
    beq     s8, t0, 63f
    bltu    s9, a1, 63f                     # max by (weight, root)
    bltu    a1, s9, 64f
    li      t0, BlockNode__mem
    mul     t4, s6, t0
    add     t4, s10, t4
    mul     t5, s8, t0
    add     t5, s10, t5
    ROOT_GT t4, t5, 63f, 64f, a2
63: mv      s8, s6
    mv      s9, a1
64: addi    s6, s6, 1
    j       62b
65: li      t0, -1
    beq     s8, t0, 66f
    mv      s7, s8
    j       61b
66: mv      a1, s7
    li      a0, LANTERN_OK
7:  LEAVE 16
END_FUNCTION head

/* s1 store, s2 out. */
SPEC_FUNCTION get_filtered_node_tree
    ENTER 0
    mv      s1, a0
    mv      s2, a2
    call    filter_tree
    bnez    a0, 7f
    ld      t0, (Store_blocks + 8)(s1)
    li      t1, 0                           # the nodes in the tree
    li      t2, 0
1:  bgeu    t2, t0, 2f
    slli    t3, t2, 3
    add     t3, a1, t3
    ld      t3, 0(t3)
    andi    t3, t3, F_VIABLE
    snez    t3, t3
    add     t1, t1, t3
    addi    t2, t2, 1
    j       1b
2:  slli    t3, t1, 3
    addi    t3, t3, LIST_FIXED
    ld      t4, 0(s2)
    bltu    t4, t3, 9f
    li      t3, LIST_FIXED
    sd      t3, LIST_OFFSET(s2)
    sd      t1, LIST_COUNT(s2)
    addi    t4, s2, LIST_FIXED
    li      t2, 0
3:  bgeu    t2, t0, 4f
    slli    t3, t2, 3
    add     t3, a1, t3
    ld      t3, 0(t3)
    andi    t3, t3, F_VIABLE
    beqz    t3, 31f
    sd      t2, 0(t4)
    addi    t4, t4, 8
31: addi    t2, t2, 1
    j       3b
4:  li      a0, LANTERN_OK
7:  LEAVE 0
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END get_filtered_node_tree

SPEC_FUNCTION get_head
    FRAME 16
    sd      a2, F(sp)
    NEED_BALANCES a0, 8f
    call    head
    bnez    a0, 7f
    ld      a2, F(sp)
    sd      a1, 0(a2)
7:  UNFRAME 16
8:  li      a0, LANTERN_NEED_JUSTIFIED_STATE
    UNFRAME 16
SPEC_END get_head

/* ---------------------------------------------------------------- Checkpoints and time */

/* L0: update_checkpoints(store a0, justified a1, finalized a2). A leaf; uses a3, a6, a7. */
LOCAL_FUNCTION update_checkpoints
    UNWIND_END_PROLOGUE
    addi    a3, a0, Store_justified_checkpoint
    RAISE   a3, a1
    addi    a3, a0, Store_finalized_checkpoint
    RAISE   a3, a2
    ret
END_FUNCTION update_checkpoints

/* L0: update_unrealized_checkpoints(store a0, justified a1, finalized a2). A leaf; uses a3, a6, a7. */
LOCAL_FUNCTION update_unrealized_checkpoints
    UNWIND_END_PROLOGUE
    addi    a3, a0, Store_unrealized_justified_checkpoint
    RAISE   a3, a1
    addi    a3, a0, Store_unrealized_finalized_checkpoint
    RAISE   a3, a2
    ret
END_FUNCTION update_unrealized_checkpoints

/* L0: on_tick_per_slot(store a0, time_ms a1), with time_ms not before genesis_time_ms. A leaf. */
LOCAL_FUNCTION on_tick_per_slot
    UNWIND_END_PROLOGUE
    STORE_SLOT a2, a0, 9f                   # previous_slot
    sd      a1, Store_time_ms(a0)
    STORE_SLOT a3, a0, 9f                   # current_slot
    bgeu    a2, a3, 9f
    sd      zero, Store_proposer_boost_root(a0)     # a new slot: proposer_boost_root = Root()
    sd      zero, (Store_proposer_boost_root + 8)(a0)
    sd      zero, (Store_proposer_boost_root + 16)(a0)
    sd      zero, (Store_proposer_boost_root + 24)(a0)
    andi    a3, a3, (SLOTS_PER_EPOCH - 1)   # a new epoch: pull up the unrealized checkpoints
    bnez    a3, 9f
    addi    a1, a0, Store_unrealized_justified_checkpoint
    addi    a2, a0, Store_unrealized_finalized_checkpoint
    j       update_checkpoints
9:  ret
END_FUNCTION on_tick_per_slot

/* s1 store, s2 time_ms, s3 result, s4 tick slot, s5 genesis_time_ms, s6 SLOT_DURATION_MS. */
SPEC_FUNCTION on_tick
    ENTER 0
    mv      s1, a0
    ld      s2, 0(a1)
    mv      s3, a2
    sd      zero, 0(s3)
    ld      s5, Store_genesis_time_ms(s1)
    ld      s6, (Store_config + CONFIG_SLOT_DURATION_MS)(s1)
    bltu    s2, s5, 6f                      # tick_slot = compute_slot_at_time_ms(genesis_time_ms, time_ms)
    sub     s4, s2, s5
    divu    s4, s4, s6
1:  STORE_SLOT t0, s1, 6f                   # catch up slot by slot
    bgeu    t0, s4, 2f
    addi    t0, t0, 1
    mul     a1, t0, s6                      # compute_time_at_slot_ms(genesis_time_ms, next_slot)
    add     a1, a1, s5
    mv      a0, s1
    call    on_tick_per_slot
    j       1b
2:  mv      a0, s1
    mv      a1, s2
    call    on_tick_per_slot
    li      a0, LANTERN_OK
    LEAVE 0
6:  li      t0, LANTERN_INVALID_OVERFLOW
    sd      t0, 0(s3)
    li      a0, LANTERN_OK
    LEAVE 0
SPEC_END on_tick

/* ---------------------------------------------------------------- The store */

/*
 * a0 store, a1 state; a2 entries, a3 entry count, a4 validators, a5 validator count,
 * t0 epoch, t1 total, t2 i, t3 cursor.
 */
SPEC_LEAF store_justified_checkpoint_state
    PART    a2, a3, a0, Store_validators
    PART    a4, a5, a1, BeaconState_validators
    bltu    a3, a5, 9f
    LDQ     t0, a1, BeaconState_slot
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH    # get_current_epoch(state)
    li      t1, 0
    li      t2, 0
    mv      t3, a4
1:  bgeu    t2, a5, 2f                      # get_total_balance of the active unslashed, before any change
    ACTIVE_UNSLASHED t4, t3, t0
    beqz    t4, 11f
    ld      t5, Validator_effective_balance(t3)
    add     t5, t1, t5
    bltu    t5, t1, 8f
    mv      t1, t5
11: addi    t3, t3, Validator__mem
    addi    t2, t2, 1
    j       1b
2:  li      t3, EFFECTIVE_BALANCE_INCREMENT
    bgeu    t1, t3, 21f
    mv      t1, t3
21: sd      t1, Store_balances_total(a0)
    li      t2, 0
3:  bgeu    t2, a3, 5f
    ld      t6, StoreValidator_flags(a2)
    andi    t6, t6, STORE_EQUIVOCATING
    li      t5, 0
    bgeu    t2, a5, 4f
    ACTIVE_UNSLASHED t4, a4, t0
    ori     t6, t6, STORE_IN_REGISTRY
    or      t6, t6, t4
    ld      t5, Validator_effective_balance(a4)
    addi    a4, a4, Validator__mem
4:  sd      t5, StoreValidator_effective_balance(a2)
    sd      t6, StoreValidator_flags(a2)
    addi    a2, a2, StoreValidator__mem
    addi    t2, t2, 1
    j       3b
5:  addi    t3, a0, Store_balances_checkpoint
    addi    t4, a0, Store_justified_checkpoint
    COPY40  t3, t4
    RETURN_OK
8:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    ret
SPEC_END store_justified_checkpoint_state

/*
 * s1 anchor state, s2 anchor block, s3 config, s4 room, s5 scratch, s6 store,
 * s7 node capacity, s8 validator capacity, s9 anchor epoch, s10 the anchor node.
 * Locals: L state root (32), L+32 anchor root (32), L+64 size.
 */
SPEC_FUNCTION get_forkchoice_store
    ENTER 80
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    ld      s7, 0(s4)
    ld      s8, 8(s4)
    beqz    s7, 9f
    LDQ     t0, s1, BeaconState_validators + 8
    bltu    s8, t0, 9f
    mv      a0, s4
    addi    a1, sp, (L + 64)
    CALL_GLOBAL lantern_store_size
    bnez    a0, 9f
    ld      t0, (L + 64)(sp)
    ld      t1, 0(s6)
    bltu    t1, t0, 9f
    ld      t0, 0(s5)
    li      t1, LANTERN_SCRATCH_FIXED
    bltu    t0, t1, 9f
    ADDRESS a0, lantern_type_BeaconState    # assert anchor_block.state_root == hash_tree_root(anchor_state)
    mv      a1, s1
    mv      a2, s5
    addi    a3, sp, L
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 7f
    addi    t5, s2, BeaconBlock_state_root
    addi    t6, sp, L
    NE32    t5, t6, 6f
    ADDRESS a0, lantern_type_BeaconBlock    # anchor_root = hash_tree_root(anchor_block)
    mv      a1, s2
    mv      a2, s5
    addi    a3, sp, (L + 32)
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 7f
    LDQ     t0, s1, BeaconState_genesis_time    # genesis_time_ms = seconds_to_milliseconds(genesis_time)
    li      t1, 1000
    mulhu   t2, t0, t1
    mul     t0, t0, t1
    beqz    t2, 1f
    li      t0, -1                          # UINT64_MAX when it does not fit
1:  LDQ     t1, s1, BeaconState_slot        # time_ms = compute_time_at_slot_ms(genesis_time_ms, anchor_state.slot)
    ld      t2, CONFIG_SLOT_DURATION_MS(s3)
    mulhu   t3, t1, t2
    bnez    t3, 5f
    mul     t3, t1, t2
    add     t3, t3, t0
    bltu    t3, t0, 5f
    sd      t3, Store_time_ms(s6)
    sd      t0, Store_genesis_time_ms(s6)
    srli    s9, t1, LOG2_SLOTS_PER_EPOCH    # anchor_epoch = get_current_epoch(anchor_state)
    addi    t1, sp, (L + 32)                # the four checkpoints: (anchor_epoch, anchor_root)
    sd      s9, Store_justified_checkpoint(s6)
    addi    t0, s6, (Store_justified_checkpoint + Checkpoint_root)
    COPY32  t0, t1
    sd      s9, Store_finalized_checkpoint(s6)
    addi    t0, s6, (Store_finalized_checkpoint + Checkpoint_root)
    COPY32  t0, t1
    sd      s9, Store_unrealized_justified_checkpoint(s6)
    addi    t0, s6, (Store_unrealized_justified_checkpoint + Checkpoint_root)
    COPY32  t0, t1
    sd      s9, Store_unrealized_finalized_checkpoint(s6)
    addi    t0, s6, (Store_unrealized_finalized_checkpoint + Checkpoint_root)
    COPY32  t0, t1
    sd      zero, Store_proposer_boost_root(s6)
    sd      zero, (Store_proposer_boost_root + 8)(s6)
    sd      zero, (Store_proposer_boost_root + 16)(s6)
    sd      zero, (Store_proposer_boost_root + 24)(s6)
    li      t0, STORE_FIXED                 # the parts: the anchor node, then the validators
    sd      t0, Store_blocks(s6)
    li      t1, 1
    sd      t1, (Store_blocks + 8)(s6)
    li      t1, BlockNode__mem
    mul     t1, s7, t1
    add     t1, t1, t0
    sd      t1, Store_validators(s6)
    sd      s8, (Store_validators + 8)(s6)
    addi    a0, s6, Store_config
    mv      a1, s3
    li      a2, CONFIG_SIZE
    call    lantern_copy
    li      t0, STORE_FIXED                 # blocks = {anchor_root: anchor_block}
    add     s10, s6, t0
    addi    t0, sp, (L + 32)
    COPY32  s10, t0
    addi    t0, s10, BlockNode_parent_root
    addi    t1, s2, BeaconBlock_parent_root
    COPY32  t0, t1
    ld      t0, BeaconBlock_slot(s2)
    sd      t0, BlockNode_slot(s10)
    ld      t0, BeaconBlock_proposer_index(s2)
    sd      t0, BlockNode_proposer_index(s10)
    li      t0, -1
    sd      t0, BlockNode_parent(s10)
    addi    t0, s10, BlockNode_justified_checkpoint     # block_states[anchor_root].current_justified_checkpoint
    ADDQ    t1, s1, BeaconState_current_justified_checkpoint
    COPY40  t0, t1
    sd      s9, BlockNode_unrealized_justified_checkpoint(s10)     # unrealized_justifications
    addi    t0, s10, (BlockNode_unrealized_justified_checkpoint + Checkpoint_root)
    addi    t1, sp, (L + 32)
    COPY32  t0, t1
    sd      zero, BlockNode_timely(s10)
.if FORK >= FORK_BELLATRIX
    PART    t0, t1, s2, BeaconBlock_body    # the anchor's payload counts as VALID
    PART    t2, t1, t0, BeaconBlockBody_execution_payload
    addi    t0, t2, ExecutionPayload_block_hash
    addi    t1, s10, BlockNode_block_hash
    COPY32  t1, t0
.else
    .irp k, 0, 8, 16, 24
    sd      zero, (BlockNode_block_hash + \k)(s10)    # no payload before bellatrix: a zero hash
    .endr
.endif
    sd      zero, BlockNode_payload_status(s10)
    PART    t0, t1, s6, Store_validators    # latest_messages = {}
    li      t2, -1
2:  beqz    t1, 3f
    sd      zero, StoreValidator_latest_epoch(t0)
    sd      t2, StoreValidator_latest_node(t0)
    sd      zero, StoreValidator_effective_balance(t0)
    sd      zero, StoreValidator_flags(t0)
    addi    t0, t0, StoreValidator__mem
    addi    t1, t1, -1
    j       2b
3:  mv      a0, s6                          # checkpoint_states = {justified_checkpoint: anchor_state}
    mv      a1, s1
    call    lantern_store_justified_checkpoint_state
7:  LEAVE 80
5:  li      a0, LANTERN_INVALID_OVERFLOW
    LEAVE 80
6:  li      a0, LANTERN_INVALID_ANCHOR
    LEAVE 80
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
SPEC_END get_forkchoice_store

/* ---------------------------------------------------------------- Attestations */

/*
 * L0: a0 = validate_on_attestation(store a0, data a1, is_from_block a2 as a value), as a status;
 * a1 = the node of the head vote. s1 store, s2 data, s3 target node, s4 head node.
 */
LOCAL_FUNCTION validate_attestation
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    ld      t0, (AttestationData_target + Checkpoint_epoch)(s2)
    bnez    a2, 1f
    STORE_SLOT t1, s1, 10f                  # validate_target_epoch_against_current_time
    srli    t1, t1, LOG2_SLOTS_PER_EPOCH    # current_epoch
    beq     t0, t1, 1f
    beqz    t1, 6f                          # previous_epoch = saturating_sub(current_epoch, 1)
    addi    t1, t1, -1
    bne     t0, t1, 6f
1:  ld      t1, AttestationData_slot(s2)
    srli    t1, t1, LOG2_SLOTS_PER_EPOCH    # target.epoch == compute_epoch_at_slot(slot)
    bne     t0, t1, 6f
    mv      a0, s1                          # target.root in store.blocks
    addi    a1, s2, (AttestationData_target + Checkpoint_root)
    call    find_node
    li      t0, -1
    beq     a0, t0, 8f
    mv      s3, a0
    mv      a0, s1                          # beacon_block_root in store.blocks
    addi    a1, s2, AttestationData_beacon_block_root
    call    find_node
    li      t0, -1
    beq     a0, t0, 8f
    mv      s4, a0
    NODE    t0, s1, s4
    ld      t0, BlockNode_slot(t0)
    ld      t1, AttestationData_slot(s2)
    bltu    t1, t0, 5f
    mv      a0, s1                          # target.root == get_checkpoint_block(beacon_block_root, target.epoch)
    mv      a1, s4
    ld      a2, (AttestationData_target + Checkpoint_epoch)(s2)
    call    checkpoint_block
    bnez    a0, 7f
    bne     a1, s3, 6f
    ld      t1, AttestationData_slot(s2)    # get_current_slot(store) >= slot + 1
    addi    t1, t1, 1
    beqz    t1, 10f
    STORE_SLOT t0, s1, 10f
    bltu    t0, t1, 4f
    mv      a1, s4
    li      a0, LANTERN_OK
7:  LEAVE 0
4:  li      a0, LANTERN_INVALID_FUTURE_SLOT
    LEAVE 0
5:  li      a0, LANTERN_INVALID_ATTESTATION_SLOT
    LEAVE 0
6:  li      a0, LANTERN_INVALID_ATTESTATION_TARGET
    LEAVE 0
8:  li      a0, LANTERN_INVALID_UNKNOWN_BLOCK
    LEAVE 0
10: li      a0, LANTERN_INVALID_OVERFLOW
    LEAVE 0
END_FUNCTION validate_attestation

SPEC_FUNCTION validate_on_attestation
    FRAME 0
    addi    a1, a1, Attestation_data
    ld      a2, 0(a2)
    call    validate_attestation
    UNFRAME 0
SPEC_END validate_on_attestation

/* Local: F the start slot. */
SPEC_FUNCTION store_target_checkpoint_state
    FRAME 16
    ld      t0, Checkpoint_epoch(a1)
    srli    t1, t0, (64 - LOG2_SLOTS_PER_EPOCH)
    bnez    t1, 6f
    slli    t0, t0, LOG2_SLOTS_PER_EPOCH    # compute_start_slot_at_epoch(target.epoch)
    sd      t0, F(sp)
    LDQ     t1, a0, BeaconState_slot
    bgeu    t1, t0, 5f
    addi    a1, sp, F                       # process_slots(base_state, start slot)
    call    lantern_process_slots
    UNFRAME 16
5:  sd      zero, 0(a4)
    li      a0, LANTERN_OK
    UNFRAME 16
6:  li      t0, LANTERN_INVALID_OVERFLOW
    sd      t0, 0(a4)
    li      a0, LANTERN_OK
    UNFRAME 16
SPEC_END store_target_checkpoint_state

/*
 * s1 store, s2 attestation, s3 is_from_block, s4 target state, s5 scratch, s6 result,
 * s7 scratch size for callees, s8 indexed attestation, s9 head vote node. Locals: L valid.
 */
SPEC_FUNCTION on_attestation
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    sd      zero, 0(s6)
    NEED_SCRATCH_B s5, s4, 8, FC_ATTEST_EXTRA, 9f
    ld      t0, 0(s5)                       # own scratch at the end: the indexed attestation
    LDQ     t1, s4, BeaconState_validators + 8
    slli    t1, t1, 3
    li      t2, IndexedAttestation__fixed + 8
    add     t1, t1, t2
    sub     s7, t0, t1
    add     s8, s5, s7
    sd      t1, 0(s8)
    mv      a0, s1                          # validate_on_attestation(store, attestation, is_from_block)
    addi    a1, s2, Attestation_data
    ld      a2, 0(s3)
    call    validate_attestation
    bnez    a0, 6f
    mv      s9, a1
    sd      s7, 0(s5)                       # get_indexed_attestation(target_state, attestation)
    mv      a0, s4
    mv      a1, s2
    mv      a2, s5
    mv      a3, s8
    call    lantern_get_indexed_attestation
    CHECK_STATUS s6, 7f, 8f
    sd      s7, 0(s5)                       # assert is_valid_indexed_attestation(target_state, indexed_attestation)
    mv      a0, s4
    mv      a1, s8
    mv      a2, s5
    addi    a3, sp, L
    call    lantern_is_valid_indexed_attestation
    CHECK_STATUS s6, 7f, 8f
    ld      t0, L(sp)
    li      a0, LANTERN_INVALID_ATTESTATION
    beqz    t0, 6f
    PART    t0, t1, s8, IndexedAttestation_attesting_indices    # update_latest_messages
    PART    t2, t3, s1, Store_validators
    beqz    t1, 8f
    addi    t4, t1, -1                      # the indices ascend: the last needs an entry
    slli    t4, t4, 3
    add     t4, t0, t4
    ld      t4, 0(t4)
    bgeu    t4, t3, 9f
    ld      t5, (Attestation_data + AttestationData_target + Checkpoint_epoch)(s2)
    li      a2, -1
1:  beqz    t1, 8f
    ld      t4, 0(t0)
    addi    t0, t0, 8
    slli    t4, t4, 5
    add     t4, t2, t4
    ld      t6, StoreValidator_flags(t4)
    andi    t6, t6, STORE_EQUIVOCATING      # in store.equivocating_indices
    bnez    t6, 2f
    ld      t6, StoreValidator_latest_node(t4)
    beq     t6, a2, 3f
    ld      t6, StoreValidator_latest_epoch(t4)
    bgeu    t6, t5, 2f                      # target.epoch > latest_messages[i].epoch
3:  sd      t5, StoreValidator_latest_epoch(t4)
    sd      s9, StoreValidator_latest_node(t4)
2:  addi    t1, t1, -1
    j       1b
8:  li      a0, LANTERN_OK
7:  LEAVE 16
6:  sd      a0, 0(s6)
    li      a0, LANTERN_OK
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END on_attestation

/*
 * s1 store, s2 attester slashing, s3 state, s4 scratch, s5 result, s6 attestation_1,
 * s7 attestation_2, s8 scratch size. Locals: L out.
 */
SPEC_FUNCTION on_attester_slashing
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    sd      zero, 0(s5)
    NEED_SCRATCH s4, s3, 7, 9f
    ld      s8, 0(s4)
    PART    s6, t0, s2, AttesterSlashing_attestation_1
    PART    s7, t0, s2, AttesterSlashing_attestation_2
    addi    a0, s6, IndexedAttestation_data # assert is_slashable_attestation_data(...)
    addi    a1, s7, IndexedAttestation_data
    addi    a2, sp, L
    call    lantern_is_slashable_attestation_data
    ld      t0, L(sp)
    beqz    t0, 6f
    mv      a0, s3                          # assert is_valid_indexed_attestation(state, attestation_1)
    mv      a1, s6
    mv      a2, s4
    addi    a3, sp, L
    call    lantern_is_valid_indexed_attestation
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 7f
    bnez    a0, 6f
    ld      t0, L(sp)
    beqz    t0, 6f
    sd      s8, 0(s4)                       # and attestation_2
    mv      a0, s3
    mv      a1, s7
    mv      a2, s4
    addi    a3, sp, L
    call    lantern_is_valid_indexed_attestation
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 7f
    bnez    a0, 6f
    ld      t0, L(sp)
    beqz    t0, 6f
    PART    t4, t5, s1, Store_validators    # the common indices: both lists ascend
    PART    t0, t1, s6, IndexedAttestation_attesting_indices
    PART    t2, t3, s7, IndexedAttestation_attesting_indices
1:  beqz    t1, 3f                          # first, every common index needs an entry
    beqz    t3, 3f
    ld      a2, 0(t0)
    ld      a3, 0(t2)
    bltu    a2, a3, 11f
    bltu    a3, a2, 12f
    bgeu    a2, t5, 9f
    addi    t0, t0, 8
    addi    t1, t1, -1
12: addi    t2, t2, 8
    addi    t3, t3, -1
    j       1b
11: addi    t0, t0, 8
    addi    t1, t1, -1
    j       1b
3:  PART    t0, t1, s6, IndexedAttestation_attesting_indices    # then equivocating_indices.add(index)
    PART    t2, t3, s7, IndexedAttestation_attesting_indices
4:  beqz    t1, 8f
    beqz    t3, 8f
    ld      a2, 0(t0)
    ld      a3, 0(t2)
    bltu    a2, a3, 41f
    bltu    a3, a2, 42f
    slli    a4, a2, 5
    add     a4, t4, a4
    ld      a5, StoreValidator_flags(a4)
    ori     a5, a5, STORE_EQUIVOCATING
    sd      a5, StoreValidator_flags(a4)
    addi    t0, t0, 8
    addi    t1, t1, -1
42: addi    t2, t2, 8
    addi    t3, t3, -1
    j       4b
41: addi    t0, t0, 8
    addi    t1, t1, -1
    j       4b
8:  li      a0, LANTERN_OK
7:  LEAVE 16
6:  li      t0, LANTERN_INVALID_ATTESTER_SLASHING
    sd      t0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END on_attester_slashing

/* ---------------------------------------------------------------- get_proposer_head */

/*
 * s1 store, s2 head node, s3 slot, s4 head state, s5 scratch, s6 out, s7 parent node,
 * s8 the conditions, s9 scratch size, s10 head weight.
 * Locals: L committee count, L+8 index, L+16 epoch, L+24 committee, L+32 reorg threshold.
 * Condition bits: 1 head_late, 2 ffg_competitive, 4 finalization_ok, 8 proposing_on_time,
 * 16 single_slot_reorg, 32 head_weak, 64 parent_strong, 128 current_time_ok, 256 proposer_equivocation.
 */
SPEC_FUNCTION get_proposer_head
    ENTER 48
    mv      s1, a0
    ld      s2, 0(a1)
    ld      s3, 0(a2)
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    NEED_BALANCES s1, 4f
    NEED_SCRATCH s5, s4, 3, 9f
    ld      s9, 0(s5)
    NODE    t0, s1, s2                      # head_block
    ld      s7, BlockNode_parent(t0)        # parent_block = store.blocks[parent_root]
    li      t1, -1
    beq     s7, t1, 8f
    NODE    t2, s1, s7
    ld      t1, BlockNode_timely(t0)        # head_late = is_head_late(store, head_node.root)
    seqz    s8, t1
    addi    t5, t0, BlockNode_unrealized_justified_checkpoint      # ffg_competitive
    addi    t6, t2, BlockNode_unrealized_justified_checkpoint
    NE40    t5, t6, 1f
    ori     s8, s8, 2
1:  srli    t1, s3, LOG2_SLOTS_PER_EPOCH    # finalization_ok = is_finalization_ok(store, slot)
    ld      t3, (Store_finalized_checkpoint + Checkpoint_epoch)(s1)
    bltu    t1, t3, 10f
    sub     t1, t1, t3
    ld      t3, (Store_config + CONFIG_REORG_MAX_EPOCHS_SINCE_FINALIZATION)(s1)
    bltu    t3, t1, 2f
    ori     s8, s8, 4
2:  STORE_SLOT t1, s1, 10f                  # proposing_on_time: get_time_into_slot_ms(store) <= cutoff
    ld      t3, (Store_config + CONFIG_SLOT_DURATION_MS)(s1)
    mul     t1, t1, t3
    ld      t4, Store_genesis_time_ms(s1)
    add     t1, t1, t4
    ld      t4, Store_time_ms(s1)
    sub     t1, t4, t1
    ld      t4, (Store_config + CONFIG_PROPOSER_REORG_CUTOFF_BPS)(s1)
    mulhu   t5, t4, t3
    bnez    t5, 10f
    mul     t4, t4, t3
    li      t5, BASIS_POINTS
    divu    t4, t4, t5                      # get_proposer_reorg_cutoff_ms()
    bltu    t4, t1, 3f
    ori     s8, s8, 8
3:  ld      t1, BlockNode_slot(t2)          # parent_slot_ok = parent_block.slot + 1 == head_block.slot
    addi    t1, t1, 1
    beqz    t1, 10f
    ld      t3, BlockNode_slot(t0)
    xor     t1, t1, t3
    seqz    t1, t1
    addi    t4, t3, 1                       # current_time_ok = head_block.slot + 1 == slot
    beqz    t4, 10f
    xor     t4, t4, s3
    seqz    t4, t4
    slli    t5, t4, 7
    or      s8, s8, t5
    and     t1, t1, t4
    slli    t1, t1, 4
    or      s8, s8, t1                      # single_slot_reorg
    addi    t5, s1, Store_proposer_boost_root       # assert store.proposer_boost_root != head_node.root
    NE32    t5, t0, 31f
    li      a0, LANTERN_INVALID_PROPOSER_BOOST
    j       7f
31: mv      a0, s1                          # is_head_weak: reorg_threshold
    ld      a1, (Store_config + CONFIG_REORG_HEAD_WEIGHT_THRESHOLD)(s1)
    call    committee_fraction
    bnez    a0, 7f
    sd      a1, (L + 32)(sp)
    mv      a0, s1                          # head_weight = get_attestation_score(store, head_node, justified_state)
    mv      a1, s2
    call    attestation_score
    bnez    a0, 7f
    mv      s10, a1
    NODE    t0, s1, s2
    ld      t0, BlockNode_slot(t0)
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    sd      t0, (L + 16)(sp)
    mv      a0, s4                          # get_committee_count_per_slot(head_state, epoch)
    addi    a1, sp, (L + 16)
    mv      a2, s5
    addi    a3, sp, L
    call    lantern_get_committee_count_per_slot
    bnez    a0, 7f
    sd      zero, (L + 8)(sp)
5:  ld      t0, (L + 8)(sp)
    ld      t1, L(sp)
    bgeu    t0, t1, 6f
    LDQ     t0, s4, BeaconState_validators + 8
    SCRATCH_LIST t1, s5, s9, 0, t0          # the committee, at the end of scratch
    sd      t1, (L + 24)(sp)
    SCRATCH_GIVE s5, s9, 1, t0
    mv      a0, s4                          # get_beacon_committee(head_state, head_block.slot, index)
    NODE    a1, s1, s2
    addi    a1, a1, BlockNode_slot
    addi    a2, sp, (L + 8)
    mv      a3, s5
    ld      a4, (L + 24)(sp)
    call    lantern_get_beacon_committee
    bnez    a0, 7f
    ld      t0, (L + 24)(sp)
    ld      t1, LIST_COUNT(t0)
    addi    t2, t0, LIST_FIXED
    PART    t3, t4, s1, Store_validators
51: beqz    t1, 52f                         # the equivocating members' effective balances
    ld      t5, 0(t2)
    addi    t2, t2, 8
    addi    t1, t1, -1
    bgeu    t5, t4, 51b
    slli    t5, t5, 5
    add     t5, t3, t5
    ld      t6, StoreValidator_flags(t5)
    andi    a2, t6, STORE_EQUIVOCATING
    beqz    a2, 51b
    andi    a2, t6, STORE_IN_REGISTRY       # justified_state.validators[index] exists
    beqz    a2, 11f
    ld      t6, StoreValidator_effective_balance(t5)
    add     t6, s10, t6
    bltu    t6, s10, 10f
    mv      s10, t6
    j       51b
52: ld      t0, (L + 8)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 8)(sp)
    j       5b
6:  ld      t0, (L + 32)(sp)                # head_weak = head_weight < reorg_threshold
    bgeu    s10, t0, 61f
    ori     s8, s8, 32
61: mv      a0, s1                          # is_parent_strong
    ld      a1, (Store_config + CONFIG_REORG_PARENT_WEIGHT_THRESHOLD)(s1)
    call    committee_fraction
    bnez    a0, 7f
    mv      s10, a1
    mv      a0, s1
    mv      a1, s7
    call    attestation_score
    bnez    a0, 7f
    bgeu    s10, a1, 62f
    ori     s8, s8, 64
62: NODE    t0, s1, s2                      # is_proposer_equivocation
    ld      t1, BlockNode_proposer_index(t0)
    ld      t2, BlockNode_slot(t0)
    PART    t3, t4, s1, Store_blocks
    li      t5, 0
63: beqz    t4, 64f
    ld      t6, BlockNode_proposer_index(t3)
    bne     t6, t1, 631f
    ld      t6, BlockNode_slot(t3)
    bne     t6, t2, 631f
    addi    t5, t5, 1
631: addi   t3, t3, BlockNode__mem
    addi    t4, t4, -1
    j       63b
64: li      t6, 1
    bgeu    t6, t5, 65f
    ori     s8, s8, 256
65:
.if FORK >= FORK_FULU
    ori     s8, s8, 512                     # fulu drops the shuffling_stable condition
.else
    andi    t0, s3, (SLOTS_PER_EPOCH - 1)   # shuffling_stable = is_shuffling_stable(slot): slot % SLOTS_PER_EPOCH != 0
    beqz    t0, 651f
    ori     s8, s8, 512
651:
.endif
    li      t0, (1 | 2 | 4 | 8 | 16 | 32 | 64 | 512)
    and     t1, s8, t0
    beq     t1, t0, 66f
    li      t0, (32 | 128 | 256)            # head_weak, current_time_ok and proposer_equivocation
    and     t1, s8, t0
    beq     t1, t0, 66f
    sd      s2, 0(s6)
    j       67f
66: sd      s7, 0(s6)                       # the parent node
67: li      a0, LANTERN_OK
7:  LEAVE 48
4:  li      a0, LANTERN_NEED_JUSTIFIED_STATE
    LEAVE 48
8:  li      a0, LANTERN_INVALID_UNKNOWN_BLOCK
    LEAVE 48
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
10: li      a0, LANTERN_INVALID_OVERFLOW
    LEAVE 48
11: li      a0, LANTERN_INVALID_VALIDATOR_INDEX
    LEAVE 48
SPEC_END get_proposer_head

/* ---------------------------------------------------------------- The merge block */

.if FORK == FORK_BELLATRIX
/* L0: a0 = 1 when the Uint256 at a0 is below the one at a1, else 0. A leaf. */
LOCAL_FUNCTION u256_lo
    UNWIND_END_PROLOGUE
    li      a4, 24                          # from the most significant u64 down
1:  add     t0, a0, a4
    ld      t0, 0(t0)
    add     t1, a1, a4
    ld      t1, 0(t1)
    bltu    t0, t1, 2f
    bltu    t1, t0, 3f
    addi    a4, a4, -8
    bgez    a4, 1b
3:  li      a0, 0
    ret
2:  li      a0, 1
    ret
END_FUNCTION u256_lo

/* (block, parent, config, out). Locals: sp+0 block, parent, config, out; sp+32 the first condition. */
SPEC_FUNCTION is_valid_terminal_pow_block
    FRAME 48
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      a2, 16(sp)
    sd      a3, 24(sp)
    addi    a0, a0, PowBlock_total_difficulty   # is_total_difficulty_reached = block.total_difficulty >= TERMINAL_TOTAL_DIFFICULTY
    ADDQ    a1, a2, CONFIG_TERMINAL_TOTAL_DIFFICULTY
    call    u256_lo
    xori    a0, a0, 1
    sd      a0, 32(sp)
    ld      a0, 8(sp)                       # is_parent_total_difficulty_valid = parent.total_difficulty < TERMINAL_TOTAL_DIFFICULTY
    addi    a0, a0, PowBlock_total_difficulty
    ld      a1, 16(sp)
    ADDQ    a1, a1, CONFIG_TERMINAL_TOTAL_DIFFICULTY
    call    u256_lo
    ld      t0, 32(sp)
    and     a0, a0, t0
    ld      t1, 24(sp)
    sd      a0, 0(t1)
    li      a0, LANTERN_OK
    UNFRAME 48
SPEC_END is_valid_terminal_pow_block

/* s1 block, s2 pow_block, s3 pow_parent, s4 config, s5 payload. Locals: L valid. */
SPEC_FUNCTION validate_merge_block
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    PART    t0, t1, s1, BeaconBlock_body
    PART    s5, t1, t0, BeaconBlockBody_execution_payload
    ADDQ    t2, s4, CONFIG_TERMINAL_BLOCK_HASH  # TERMINAL_BLOCK_HASH != Hash32(): the override
    ld      t0, 0(t2)
    ld      t1, 8(t2)
    or      t0, t0, t1
    ld      t1, 16(t2)
    or      t0, t0, t1
    ld      t1, 24(t2)
    or      t0, t0, t1
    beqz    t0, 1f
    LDQ     t0, s1, BeaconBlock_slot        # assert compute_epoch_at_slot(block.slot) >= TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    LDQ     t1, s4, CONFIG_TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH
    bltu    t0, t1, 6f
    ADDQ    t3, s5, ExecutionPayload_parent_hash    # assert payload.parent_hash == TERMINAL_BLOCK_HASH
    NE32    t3, t2, 6f
    j       8f
1:  beqz    s2, 6f                          # assert pow_block is not None: get_pow_block(payload.parent_hash)
    ADDQ    t3, s5, ExecutionPayload_parent_hash
    ADDQ    t4, s2, PowBlock_block_hash
    NE32    t3, t4, 6f
    beqz    s3, 6f                          # assert pow_parent is not None: get_pow_block(pow_block.parent_hash)
    ADDQ    t3, s2, PowBlock_parent_hash
    ADDQ    t4, s3, PowBlock_block_hash
    NE32    t3, t4, 6f
    mv      a0, s2                          # assert is_valid_terminal_pow_block(pow_block, pow_parent)
    mv      a1, s3
    mv      a2, s4
    addi    a3, sp, L
    call    lantern_is_valid_terminal_pow_block
    ld      t0, L(sp)
    beqz    t0, 6f
8:  li      a0, LANTERN_OK
    LEAVE 16
6:  li      a0, LANTERN_INVALID_MERGE_BLOCK
    LEAVE 16
SPEC_END validate_merge_block
.endif

/* ---------------------------------------------------------------- on_block */

/*
 * s1 store, s2 signed block, s3 state, s4 options, s5 scratch, s6 result, s7 block,
 * s8 scratch size, s9 parent node, s10 dependent slot, then the new node.
 * Locals: L block root (32), L+32 transition options (24, then L+48 the head), L+56 current slot,
 * L+64 pulled up justified (40), L+104 pulled up finalized (40), L+144 saved justification bits,
 * L+152 saved previous justified (40), L+192 saved current justified (40), L+232 saved finalized (40),
 * L+272 its result, L+280 timely, L+288 head dependent node, then the boost, L+296 bellatrix: is_merge_transition_block.
 */
SPEC_FUNCTION on_block
    ENTER 304
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    sd      zero, 0(s6)
    PART    s7, t0, s2, SignedBeaconBlock_message
    ld      s8, 0(s5)
    ADDRESS a0, lantern_type_BeaconBlock    # block_root = hash_tree_root(block)
    mv      a1, s7
    mv      a2, s5
    addi    a3, sp, L
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 7f
    mv      a0, s1                          # return early if the block is already known
    addi    a1, sp, L
    call    find_node
    li      t0, -1
    bne     a0, t0, 8f
    mv      a0, s1                          # assert block.parent_root in store.block_states
    addi    a1, s7, BeaconBlock_parent_root
    call    find_node
    mv      s9, a0
    li      t0, -1
    li      a0, LANTERN_INVALID_UNKNOWN_BLOCK
    beq     s9, t0, 6f
    NODE    t0, s1, s9                      # the parent's payload is not INVALIDATED (optimistic sync)
    ld      t0, BlockNode_payload_status(t0)
    li      t1, PAYLOAD_STATUS_INVALIDATED
    li      a0, LANTERN_INVALID_PARENT_PAYLOAD
    beq     t0, t1, 6f
    STORE_SLOT t0, s1, 5f                   # assert get_current_slot(store) >= block.slot
    sd      t0, (L + 56)(sp)
    ld      t1, BeaconBlock_slot(s7)
    li      a0, LANTERN_INVALID_FUTURE_SLOT
    bltu    t0, t1, 6f
    ld      t0, (Store_finalized_checkpoint + Checkpoint_epoch)(s1)
    srli    t2, t0, (64 - LOG2_SLOTS_PER_EPOCH)
    bnez    t2, 5f
    slli    t2, t0, LOG2_SLOTS_PER_EPOCH    # assert block.slot > finalized_slot
    li      a0, LANTERN_INVALID_NOT_FINALIZED
    bgeu    t2, t1, 6f
    mv      a0, s1                          # finalized_checkpoint_block of the parent
    mv      a1, s9
    mv      a2, t0
    call    checkpoint_block
    bnez    a0, 6f
    NODE    t5, s1, a1
    addi    t6, s1, (Store_finalized_checkpoint + Checkpoint_root)
    li      a0, LANTERN_INVALID_NOT_FINALIZED
    NE32    t5, t6, 6f
.if FORK >= FORK_DENEB
    ld      t0, BlockOptions_data_available(s4)     # assert is_data_available(block_root)
    li      a0, LANTERN_INVALID_DATA_UNAVAILABLE
    beqz    t0, 6f
.endif
    ld      t0, (Store_blocks + 8)(s1)      # before the state changes: room for the node
    ld      t1, Store_blocks(s1)
    ld      t2, Store_validators(s1)
    sub     t2, t2, t1
    li      t3, BlockNode__mem
    divu    t2, t2, t3
    bgeu    t0, t2, 9f
    NEED_BALANCES s1, 4f                    # the justified checkpoint state, for get_head
    slli    t0, t0, 3                       # scratch for get_head
    addi    t0, t0, LIST_FIXED
    li      t1, LANTERN_SCRATCH_FIXED
    add     t0, t0, t1
    bltu    s8, t0, 9f
.if FORK == FORK_BELLATRIX
    mv      a0, s3                          # is_merge_transition_block(pre_state, block.body), before the state changes
    PART    a1, t0, s7, BeaconBlock_body
    addi    a2, sp, (L + 296)
    call    lantern_is_merge_transition_block
.endif
    li      t0, 1                           # state_transition(state, signed_block, validate_result=True)
    sd      t0, (L + 32)(sp)
    ld      t1, BlockOptions_payload_status(s4)
    addi    t1, t1, -PAYLOAD_STATUS_INVALIDATED
    snez    t1, t1                          # execution_valid: VALID or NOT_VALIDATED
    sd      t1, (L + 40)(sp)
    ld      t1, BlockOptions_slots_done(s4)
    sd      t1, (L + 48)(sp)
    mv      a0, s3
    mv      a1, s2
    addi    a2, sp, (L + 32)
    addi    a3, s1, Store_config
    mv      a4, s5
    mv      a5, s6
    call    lantern_state_transition
    bnez    a0, 7f
    ld      t0, 0(s6)
    bnez    t0, 8f
.if FORK == FORK_BELLATRIX
    ld      t0, (L + 296)(sp)               # if is_merge_transition_block(pre_state, block.body): validate_merge_block(block)
    beqz    t0, 1f
    mv      a0, s7
    ld      a1, BlockOptions_pow_block(s4)
    ld      a2, BlockOptions_pow_parent(s4)
    addi    a3, s1, Store_config
    call    lantern_validate_merge_block
    bnez    a0, 6f
1:
.endif
    sd      s8, 0(s5)                       # head = get_head(store), before the block is added
    mv      a0, s1
    mv      a1, s5
    call    head
    bnez    a0, 6f
    sd      a1, (L + 48)(sp)
    ADDQ    t5, s3, BeaconState_justification_bits  # compute_pulled_up_tip: on a copy of the fields it changes
    lbu     t0, 0(t5)
    sd      t0, (L + 144)(sp)
    ADDQ    t5, s3, BeaconState_previous_justified_checkpoint
    addi    t6, sp, (L + 152)
    COPY40  t6, t5
    ADDQ    t5, s3, BeaconState_current_justified_checkpoint
    addi    t6, sp, (L + 192)
    COPY40  t6, t5
    ADDQ    t5, s3, BeaconState_finalized_checkpoint
    addi    t6, sp, (L + 232)
    COPY40  t6, t5
    sd      s8, 0(s5)
    mv      a0, s3                          # process_justification_and_finalization(state)
    addi    a1, s1, Store_config
    mv      a2, s5
    addi    a3, sp, (L + 272)
    call    lantern_process_justification_and_finalization
    mv      s10, a0
    ADDQ    t5, s3, BeaconState_current_justified_checkpoint
    addi    t6, sp, (L + 64)
    COPY40  t6, t5
    ADDQ    t5, s3, BeaconState_finalized_checkpoint
    addi    t6, sp, (L + 104)
    COPY40  t6, t5
    ld      t0, (L + 144)(sp)               # the post-state again
    ADDQ    t5, s3, BeaconState_justification_bits
    sb      t0, 0(t5)
    ADDQ    t5, s3, BeaconState_previous_justified_checkpoint
    addi    t6, sp, (L + 152)
    COPY40  t5, t6
    ADDQ    t5, s3, BeaconState_current_justified_checkpoint
    addi    t6, sp, (L + 192)
    COPY40  t5, t6
    ADDQ    t5, s3, BeaconState_finalized_checkpoint
    addi    t6, sp, (L + 232)
    COPY40  t5, t6
    mv      a0, s10
    bnez    a0, 7f
    ld      a0, (L + 272)(sp)
    bnez    a0, 6f
    ld      t0, (L + 56)(sp)                # record_block_timeliness
    ld      t1, (Store_config + CONFIG_SLOT_DURATION_MS)(s1)
    mul     t3, t0, t1
    ld      t2, Store_genesis_time_ms(s1)
    add     t3, t3, t2
    ld      t2, Store_time_ms(s1)
    sub     t3, t2, t3                      # time_into_slot_ms
    ld      t4, (Store_config + CONFIG_ATTESTATION_DUE_BPS)(s1)
    mulhu   t5, t4, t1
    bnez    t5, 5f
    mul     t4, t4, t1
    li      t5, BASIS_POINTS
    divu    t4, t4, t5                      # get_attestation_due_ms()
    sltu    t5, t3, t4                      # is_before_attesting_interval
    ld      t6, BeaconBlock_slot(s7)
    beq     t0, t6, 40f
    li      t5, 0                           # is_timely
40: sd      t5, (L + 280)(sp)
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH    # update_proposer_boost_root: the dependent slot of the current epoch
    li      t1, MIN_SEED_LOOKAHEAD
    sub     t1, t0, t1
    bgeu    t0, t1, 401f                    # saturating_sub(epoch, MIN_SEED_LOOKAHEAD)
    li      t1, 0
401: slli   t0, t1, LOG2_SLOTS_PER_EPOCH
    beqz    t0, 402f
    addi    t0, t0, -1
402: mv     s10, t0
    mv      a0, s1                          # head_dependent_root
    ld      a1, (L + 48)(sp)
    mv      a2, s10
    call    ancestor
    bnez    a0, 6f
    sd      a1, (L + 288)(sp)
    ld      t1, (Store_blocks + 8)(s1)      # block_dependent_root: the new node, or an ancestor of its parent
    ld      t0, BeaconBlock_slot(s7)
    bgeu    s10, t0, 41f
    mv      a0, s1
    mv      a1, s9
    mv      a2, s10
    call    ancestor
    bnez    a0, 6f
    mv      t1, a1
41: ld      t0, (L + 288)(sp)
    xor     t0, t0, t1
    seqz    t0, t0                          # is_same_dependent_root
    ld      t1, (L + 280)(sp)
    and     t0, t0, t1
    ld      t1, Store_proposer_boost_root(s1)       # is_first_block
    ld      t2, (Store_proposer_boost_root + 8)(s1)
    ld      t3, (Store_proposer_boost_root + 16)(s1)
    ld      t4, (Store_proposer_boost_root + 24)(s1)
    or      t1, t1, t2
    or      t3, t3, t4
    or      t1, t1, t3
    beqz    t1, 43f
    li      t0, 0
43: sd      t0, (L + 288)(sp)
    ld      t0, (Store_blocks + 8)(s1)      # every check holds: the writes, in spec order
    addi    t1, t0, 1
    sd      t1, (Store_blocks + 8)(s1)
    NODE    s10, s1, t0                     # store.blocks[block_root] = block
    addi    t0, sp, L
    COPY32  s10, t0
    addi    t0, s10, BlockNode_parent_root
    addi    t1, s7, BeaconBlock_parent_root
    COPY32  t0, t1
    ld      t0, BeaconBlock_slot(s7)
    sd      t0, BlockNode_slot(s10)
    ld      t0, BeaconBlock_proposer_index(s7)
    sd      t0, BlockNode_proposer_index(s10)
    sd      s9, BlockNode_parent(s10)
    addi    t0, s10, BlockNode_justified_checkpoint    # block_states[block_root].current_justified_checkpoint
    ADDQ    t1, s3, BeaconState_current_justified_checkpoint
    COPY40  t0, t1
    addi    t0, s10, BlockNode_unrealized_justified_checkpoint     # unrealized_justifications[block_root]
    addi    t1, sp, (L + 64)
    COPY40  t0, t1
    ld      t0, (L + 280)(sp)               # block_timeliness[block_root]
    sd      t0, BlockNode_timely(s10)
.if FORK >= FORK_BELLATRIX
    PART    t0, t1, s7, BeaconBlock_body    # the payload's hash and status
    PART    t2, t1, t0, BeaconBlockBody_execution_payload
    addi    t0, t2, ExecutionPayload_block_hash
    addi    t1, s10, BlockNode_block_hash
    COPY32  t1, t0
.else
    .irp k, 0, 8, 16, 24
    sd      zero, (BlockNode_block_hash + \k)(s10)    # no payload before bellatrix: a zero hash
    .endr
.endif
    ld      t0, BlockOptions_payload_status(s4)
    sd      t0, BlockNode_payload_status(s10)
    bnez    t0, 44f                         # VALID: so are its NOT_VALIDATED ancestors
    mv      t1, s9
    li      t3, PAYLOAD_STATUS_NOT_VALIDATED
43: li      t0, -1
    beq     t1, t0, 44f
    NODE    t2, s1, t1
    ld      t0, BlockNode_payload_status(t2)
    bne     t0, t3, 44f
    sd      zero, BlockNode_payload_status(t2)
    ld      t1, BlockNode_parent(t2)
    j       43b
44:
    ld      t0, (L + 288)(sp)               # proposer_boost_root = block_root
    beqz    t0, 42f
    addi    t0, s1, Store_proposer_boost_root
    addi    t1, sp, L
    COPY32  t0, t1
42: mv      a0, s1                          # update_checkpoints(store, state.current_justified, state.finalized)
    ADDQ    a1, s3, BeaconState_current_justified_checkpoint
    ADDQ    a2, s3, BeaconState_finalized_checkpoint
    call    update_checkpoints
    mv      a0, s1                          # compute_pulled_up_tip
    addi    a1, sp, (L + 64)
    addi    a2, sp, (L + 104)
    call    update_unrealized_checkpoints
    ld      t0, BeaconBlock_slot(s7)
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    ld      t1, (L + 56)(sp)
    srli    t1, t1, LOG2_SLOTS_PER_EPOCH
    bgeu    t0, t1, 8f                      # a block from a prior epoch: the realized values
    mv      a0, s1
    addi    a1, sp, (L + 64)
    addi    a2, sp, (L + 104)
    call    update_checkpoints
8:  li      a0, LANTERN_OK
7:  LEAVE 304
6:  sd      a0, 0(s6)
    li      a0, LANTERN_OK
    LEAVE 304
5:  li      a0, LANTERN_INVALID_OVERFLOW
    j       6b
4:  li      a0, LANTERN_NEED_JUSTIFIED_STATE
    LEAVE 304
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 304
SPEC_END on_block

/* ---------------------------------------------------------------- Data availability */

.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
/*
 * (blob_kzg_commitments, blobs, proofs, settings, scratch, out): verify_blob_kzg_proof_batch of the blobs
 * and proofs that retrieve_blobs_and_proofs gave. Locals: sp+0 out.
 */
SPEC_FUNCTION is_data_available
    FRAME 16
    sd      a5, 0(sp)
    mv      t0, a0                          # asm-crypto: settings, blobs, commitments, proofs, scratch, valid
    mv      a0, a3
    mv      t1, a2
    mv      a2, t0
    mv      a3, t1
    CALL_GLOBAL crypto_kzg_verify_blob_kzg_proof_batch
    li      t0, CRYPTO_BUFFER_TOO_SMALL
    beq     a0, t0, 9f
    beqz    a0, 8f
    ld      t1, 0(sp)                       # a KZG input that fails its checks: the spec's exception, not available
    sd      zero, 0(t1)
8:  li      a0, LANTERN_OK
    UNFRAME 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    UNFRAME 16
SPEC_END is_data_available
.endif

.if FORK >= FORK_FULU

/* s1 sidecar, s2 config, s3 out. Locals: L epoch, L+8 blob parameters (16). */
SPEC_FUNCTION verify_data_column_sidecar
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    sd      zero, 0(s3)
    ld      t0, DataColumnSidecar_index(s1) # sidecar.index < NUMBER_OF_COLUMNS
    li      t1, NUMBER_OF_COLUMNS
    bgeu    t0, t1, 8f
    LDQ     t0, s1, DataColumnSidecar_kzg_commitments + 8
    beqz    t0, 8f                          # a sidecar for zero blobs is invalid
    LDQ     t1, s1, DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_slot
    srli    t1, t1, LOG2_SLOTS_PER_EPOCH
    sd      t1, L(sp)
    addi    a0, sp, L                       # get_blob_parameters(epoch).max_blobs_per_block
    mv      a1, s2
    addi    a2, sp, (L + 8)
    call    lantern_get_blob_parameters
    LDQ     t0, s1, DataColumnSidecar_kzg_commitments + 8
    ld      t1, (L + 16)(sp)
    bltu    t1, t0, 8f
    LDQ     t1, s1, DataColumnSidecar_column + 8
    bne     t1, t0, 8f
    LDQ     t1, s1, DataColumnSidecar_kzg_proofs + 8
    bne     t1, t0, 8f
    li      t0, 1
    sd      t0, 0(s3)
8:  li      a0, LANTERN_OK
    LEAVE 32
SPEC_END verify_data_column_sidecar

/* A list of s5 entries of stride bytes at the end of scratch s3, below s10: reg = its address. Uses t0, t1. */
.macro DA_LIST reg, stride
    li      t0, \stride
    mul     t0, s5, t0
    addi    t0, t0, LIST_FIXED
    sub     s10, s10, t0
    add     \reg, s3, s10
    sd      t0, LIST_SIZE(\reg)
    li      t1, LIST_FIXED
    sd      t1, LIST_OFFSET(\reg)
    sd      s5, LIST_COUNT(\reg)
.endm

/*
 * s1 sidecar, s2 settings, s3 scratch, s4 out, s5 n, s6 commitments, s7 cell indices,
 * s8 cells, s9 proofs, s10 scratch size left. Locals: L valid.
 */
SPEC_FUNCTION verify_data_column_sidecar_kzg_proofs
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    sd      zero, 0(s4)
    LDQ     s5, s1, DataColumnSidecar_kzg_commitments + 8
    li      t0, DA_SCRATCH_PER_BLOB
    mulhu   t1, s5, t0
    bnez    t1, 9f
    mul     t0, s5, t0
    li      t1, DA_SCRATCH_FIXED
    add     t1, t0, t1
    bltu    t1, t0, 9f
    ld      s10, 0(s3)
    bltu    s10, t1, 9f
    DA_LIST s6, 48                          # commitments_bytes = sidecar.kzg_commitments
    DA_LIST s7, 8                           # cell_indices = [sidecar.index] * len(sidecar.column)
    DA_LIST s8, CRYPTO_KZG_CELL_SIZE        # cells = sidecar.column
    DA_LIST s9, 48                          # proofs_bytes = sidecar.kzg_proofs
    addi    a0, s6, LIST_FIXED
    PART    a1, a2, s1, DataColumnSidecar_kzg_commitments
    li      t0, 48
    mul     a2, a2, t0
    call    lantern_copy
    ld      t0, DataColumnSidecar_index(s1)
    addi    t1, s7, LIST_FIXED
    mv      t2, s5
1:  beqz    t2, 2f
    sd      t0, 0(t1)
    addi    t1, t1, 8
    addi    t2, t2, -1
    j       1b
2:  addi    a0, s8, LIST_FIXED
    PART    a1, a2, s1, DataColumnSidecar_column
    slli    a2, a2, 11
    call    lantern_copy
    addi    a0, s9, LIST_FIXED
    PART    a1, a2, s1, DataColumnSidecar_kzg_proofs
    li      t0, 48
    mul     a2, a2, t0
    call    lantern_copy
    sd      s10, 0(s3)                      # asm-crypto's scratch: the front
    mv      a0, s2
    mv      a1, s6
    mv      a2, s7
    mv      a3, s8
    mv      a4, s9
    mv      a5, s3
    addi    a6, sp, L
    CALL_GLOBAL crypto_kzg_verify_cell_kzg_proof_batch
    li      t0, CRYPTO_BUFFER_TOO_SMALL
    beq     a0, t0, 9f
    bnez    a0, 8f                          # an input that does not decode: the spec raises
    ld      t0, L(sp)
    sd      t0, 0(s4)
8:  li      a0, LANTERN_OK
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END verify_data_column_sidecar_kzg_proofs

/* s1 sidecar, s2 settings, s3 config, s4 scratch, s5 out, s6 sidecars left, s7 scratch size. */
SPEC_FUNCTION is_data_available
    ENTER 16
    PART    s1, s6, a0, 8                   # a standalone list: its PartRef at 8
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      s7, 0(s4)
    li      t0, 1                           # all([]) is True
    sd      t0, 0(s5)
1:  beqz    s6, 8f
    mv      a0, s1                          # verify_data_column_sidecar(column_sidecar)
    mv      a1, s3
    mv      a2, s5
    call    lantern_verify_data_column_sidecar
    ld      t0, 0(s5)
    beqz    t0, 8f
    sd      s7, 0(s4)                       # and verify_data_column_sidecar_kzg_proofs(column_sidecar)
    mv      a0, s1
    mv      a1, s2
    mv      a2, s4
    mv      a3, s5
    call    lantern_verify_data_column_sidecar_kzg_proofs
    bnez    a0, 7f
    ld      t0, 0(s5)
    beqz    t0, 8f
    ld      t0, 0(s1)
    add     s1, s1, t0
    addi    s6, s6, -1
    j       1b
8:  li      a0, LANTERN_OK
7:  LEAVE 16
SPEC_END is_data_available
.endif
