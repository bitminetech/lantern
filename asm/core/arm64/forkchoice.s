/*
 * Fork choice, ARM64. Requirements: docs/reference/fork-choice.md.
 * A ForkChoiceNode is the index of its BlockNode in the store.
 */

.set FC_ATTEST_EXTRA, IndexedAttestation__fixed + 8 + CIDX_BYTES

/* get_head: the flags of each node, a u64 each at the end of scratch. */
.set F_SUBTREE, 1          /* in the subtree of the justified node */
.set F_CHILD, 2            /* has a child */
.set F_VIABLE, 4           /* in get_filtered_node_tree */
.set F_CHILD_VIABLE, 8     /* has a child in get_filtered_node_tree */
.set F_OVERFLOW, 16        /* its weight passed 2^64 - 1 */

.if BlockNode__mem != 224 || StoreValidator__mem != 32 || Checkpoint__mem != 40 || Checkpoint_root != 8
.error "the fork choice code assumes the layouts of include/lantern.inc"
.endif
.if PAYLOAD_STATUS_VALID != 0 || PAYLOAD_STATUS_INVALIDATED != 1
.error "the fork choice code tests PAYLOAD_STATUS_VALID as 0"
.endif
.if STORE_ACTIVE_UNSLASHED != 1 || STORE_EQUIVOCATING != 2 || STORE_IN_REGISTRY != 4
.error "the fork choice code tests the StoreValidator flags by bit number"
.endif
.if CRYPTO_KZG_CELL_SIZE != BYTES_PER_FIELD_ELEMENT * FIELD_ELEMENTS_PER_CELL
.error "a Cell of the spec is not a cell of asm-crypto"
.endif

/* ---------------------------------------------------------------- Macros */

/* dst = the address of node idx of store st. Uses x16, x17. */
.macro NODE dst, st, idx
    LDQ     x16, \st, Store_blocks
    add     x16, \st, x16
    mov     x17, #BlockNode__mem
    madd    \dst, \idx, x17, x16
.endm

/* dst = get_current_slot(store st); branch to fail when time_ms is before genesis_time_ms. Uses x16. */
.macro STORE_SLOT dst, st, fail
    ldr     \dst, [\st, #Store_time_ms]
    ldr     x16, [\st, #Store_genesis_time_ms]
    subs    \dst, \dst, x16
    b.lo    \fail
    LDQ     x16, \st, Store_config + CONFIG_SLOT_DURATION_MS
    udiv    \dst, \dst, x16
.endm

/* The 40-byte Checkpoint at dst = the one at src. Uses x16, x17. */
.macro COPY40 dst, src
    ldp     x16, x17, [\src]
    stp     x16, x17, [\dst]
    ldp     x16, x17, [\src, #16]
    stp     x16, x17, [\dst, #16]
    ldr     x16, [\src, #32]
    str     x16, [\dst, #32]
.endm

/* Branch to label when the Checkpoints at a and at b differ. Uses x10-x13. */
.macro NE40 a, b, label
    NE32    \a, \b, \label
    ldr     x10, [\a, #32]
    ldr     x11, [\b, #32]
    cmp     x10, x11
    b.ne    \label
.endm

/* Branch to fail when the balances of store st are not those of its justified checkpoint. Uses x10-x15. */
.macro NEED_BALANCES st, fail
    add     x14, \st, #Store_balances_checkpoint
    add     x15, \st, #Store_justified_checkpoint
    NE40    x14, x15, \fail
.endm

/* The Checkpoint at dst = the one at src when src's epoch is greater (lantern_update_checkpoints). Uses x16, x17. */
.macro RAISE dst, src
    ldr     x16, [\src, #Checkpoint_epoch]
    ldr     x17, [\dst, #Checkpoint_epoch]
    cmp     x16, x17
    b.ls    98f
    COPY40  \dst, \src
98:
.endm

/* One u64 of a root comparison: the bytes at a + k and b + k as a big endian number. Uses x15, x16. */
.macro ROOT_STEP a, b, k, gt, le
    ldr     x15, [\a, #\k]
    ldr     x16, [\b, #\k]
    rev     x15, x15
    rev     x16, x16
    cmp     x15, x16
    b.hi    \gt
    b.lo    \le
.endm

/* Branch to gt when the root at a is greater than the root at b as a byte string, else to le. */
.macro ROOT_GT a, b, gt, le
    ROOT_STEP \a, \b, 0, \gt, \le
    ROOT_STEP \a, \b, 8, \gt, \le
    ROOT_STEP \a, \b, 16, \gt, \le
    ROOT_STEP \a, \b, 24, \gt, \le
    b       \le
.endm

/* dst = 1 when validator v is active at epoch and not slashed, else 0. Uses x13-x15. */
.macro ACTIVE_UNSLASHED dst, v, epoch
    ldr     x13, [\v, #Validator_activation_epoch]
    ldr     x14, [\v, #Validator_exit_epoch]
    ldrb    w15, [\v, #Validator_slashed]
    cmp     x13, \epoch                     /* activation_epoch <= epoch */
    ccmp    \epoch, x14, #2, ls             /* and epoch < exit_epoch; else C set, so lo fails */
    cset    \dst, lo
    cmp     w15, #0
    csel    \dst, \dst, xzr, eq
.endm

/* ---------------------------------------------------------------- Nodes */

/* x0 = the node of the root at x1 in store x0, or NODE_NONE. A leaf; uses x2-x11. */
LOCAL_FUNCTION lantern_find_node
    UNWIND_END_PROLOGUE
    PART    x2, x3, x0, Store_blocks
    ldp     x4, x5, [x1]
    ldp     x6, x7, [x1, #16]
    mov     x8, #BlockNode__mem
1:  cbz     x3, 9f                          /* newest first */
    sub     x3, x3, #1
    madd    x9, x3, x8, x2
    ldp     x10, x11, [x9]
    cmp     x10, x4
    ccmp    x11, x5, #0, eq
    b.ne    1b
    ldp     x10, x11, [x9, #16]
    cmp     x10, x6
    ccmp    x11, x7, #0, eq
    b.ne    1b
    mov     x0, x3
    ret
9:  mov     x0, #-1                         /* NODE_NONE */
    ret
END_FUNCTION lantern_find_node

/* x0 = status, x1 = get_ancestor(store x0, node x1, slot x2). A leaf; uses x3-x6, x16. */
LOCAL_FUNCTION lantern_ancestor
    UNWIND_END_PROLOGUE
    LDQ     x3, x0, Store_blocks
    add     x3, x0, x3
    mov     x4, #BlockNode__mem
1:  madd    x5, x1, x4, x3
    ldr     x6, [x5, #BlockNode_slot]
    cmp     x6, x2
    b.ls    2f
    ldr     x1, [x5, #BlockNode_parent]     /* the parent, when it is in the store */
    cmn     x1, #1
    b.ne    1b
    mov     x0, #LANTERN_INVALID_UNKNOWN_BLOCK
    ret
2:  mov     x0, #LANTERN_OK
    ret
END_FUNCTION lantern_ancestor

/* x0 = status, x1 = the node of get_checkpoint_block(store x0, node x1, epoch x2). A leaf. */
LOCAL_FUNCTION lantern_checkpoint_block
    UNWIND_END_PROLOGUE
    lsr     x3, x2, #(64 - LOG2_SLOTS_PER_EPOCH)    /* compute_start_slot_at_epoch(epoch) fits */
    cbnz    x3, 9f
    lsl     x2, x2, #LOG2_SLOTS_PER_EPOCH
    b       lantern_ancestor
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_checkpoint_block

SPEC_LEAF get_current_slot
    STORE_SLOT x2, x0, 9f
    str     x2, [x1]
    RETURN_OK
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
SPEC_END get_current_slot

SPEC_LEAF get_current_store_epoch
    STORE_SLOT x2, x0, 9f
    lsr     x2, x2, #LOG2_SLOTS_PER_EPOCH
    str     x2, [x1]
    RETURN_OK
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
SPEC_END get_current_store_epoch

SPEC_FUNCTION get_ancestor
    FRAME 16
    str     x3, [sp, #16]
    ldr     x1, [x1]
    ldr     x2, [x2]
    bl      lantern_ancestor
    cbnz    x0, 1f
    ldr     x3, [sp, #16]
    str     x1, [x3]
1:  UNFRAME 16
SPEC_END get_ancestor

/* Locals: sp+16 store, sp+24 out, sp+32 epoch. */
SPEC_FUNCTION get_checkpoint_block
    FRAME 32
    stp     x0, x3, [sp, #16]
    ldr     x2, [x2]
    str     x2, [sp, #32]
    bl      lantern_find_node
    cmn     x0, #1
    b.eq    8f
    mov     x1, x0
    ldr     x0, [sp, #16]
    ldr     x2, [sp, #32]
    bl      lantern_checkpoint_block
    cbnz    x0, 7f
    ldp     x0, x3, [sp, #16]
    NODE    x1, x0, x1
    COPY32  x3, x1
    mov     x0, #LANTERN_OK
7:  UNFRAME 32
8:  mov     x0, #LANTERN_INVALID_UNKNOWN_BLOCK
    UNFRAME 32
SPEC_END get_checkpoint_block

/* ---------------------------------------------------------------- Weights */

/*
 * x0 = status, x1 = get_attestation_score(store x0, node x1) with the store's balances.
 * A leaf; uses x2-x13. An overflow is reported after the sum, as the spec's Gwei does.
 */
LOCAL_FUNCTION lantern_attestation_score
    UNWIND_END_PROLOGUE
    LDQ     x2, x0, Store_blocks
    add     x2, x0, x2                      /* the nodes */
    mov     x3, #BlockNode__mem
    madd    x4, x1, x3, x2
    ldr     x4, [x4, #BlockNode_slot]       /* store.blocks[node.root].slot */
    PART    x5, x6, x0, Store_validators
    mov     x7, #0                          /* the sum */
    mov     x12, #0                         /* carries */
1:  cbz     x6, 5f
    sub     x6, x6, #1
    ldr     x8, [x5, #StoreValidator_flags]
    and     x8, x8, #(STORE_ACTIVE_UNSLASHED | STORE_EQUIVOCATING)
    cmp     x8, #STORE_ACTIVE_UNSLASHED     /* unslashed and active, not equivocating */
    b.ne    4f
    ldr     x9, [x5, #StoreValidator_latest_node]
    cmn     x9, #1                          /* index in store.latest_messages */
    b.eq    4f
    madd    x10, x9, x3, x2                 /* not a vote for an INVALIDATED block (optimistic sync) */
    ldr     x11, [x10, #BlockNode_payload_status]
    cmp     x11, #PAYLOAD_STATUS_INVALIDATED
    b.eq    4f
2:  madd    x10, x9, x3, x2                 /* is_ancestor(latest message node, node) */
    ldr     x11, [x10, #BlockNode_slot]
    cmp     x11, x4
    b.ls    3f
    ldr     x9, [x10, #BlockNode_parent]
    cmn     x9, #1
    b.ne    2b
    mov     x0, #LANTERN_INVALID_UNKNOWN_BLOCK
    ret
3:  cmp     x9, x1
    b.ne    4f
    ldr     x10, [x5, #StoreValidator_effective_balance]
    adds    x7, x7, x10
    cinc    x12, x12, cs
4:  add     x5, x5, #StoreValidator__mem
    b       1b
5:  cbnz    x12, 9f
    mov     x1, x7
    mov     x0, #LANTERN_OK
    ret
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_attestation_score

/*
 * x0 = status, x1 = calculate_committee_fraction(justified state, percent x1), from the
 * store's total balance. A leaf; uses x2, x3.
 */
LOCAL_FUNCTION lantern_committee_fraction
    UNWIND_END_PROLOGUE
    ldr     x2, [x0, #Store_balances_total]
    lsr     x2, x2, #LOG2_SLOTS_PER_EPOCH   /* committee_weight = total_balance // SLOTS_PER_EPOCH */
    umulh   x3, x2, x1
    cbnz    x3, 9f
    mul     x2, x2, x1
    mov     x3, #100
    udiv    x1, x2, x3
    mov     x0, #LANTERN_OK
    ret
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_committee_fraction

/* x0 = status, x1 = get_weight(store x0, node x1) with the store's balances. x19 store, x20 node, x21 score. */
LOCAL_FUNCTION lantern_weight
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    bl      lantern_attestation_score
    cbnz    x0, 7f
    mov     x21, x1
    add     x1, x19, #Store_proposer_boost_root
    ldp     x9, x10, [x1]
    ldp     x11, x12, [x1, #16]
    orr     x9, x9, x10
    orr     x11, x11, x12
    orr     x9, x9, x11
    cbz     x9, 6f                          /* no proposer_boost_root: the attestation score */
    mov     x0, x19
    bl      lantern_find_node
    cmn     x0, #1
    b.eq    8f
    NODE    x9, x19, x0                     /* no boost from an INVALIDATED block (optimistic sync) */
    ldr     x9, [x9, #BlockNode_payload_status]
    cmp     x9, #PAYLOAD_STATUS_INVALIDATED
    b.eq    6f
    mov     x1, x0                          /* is_ancestor(store, proposer_boost_node, node) */
    NODE    x9, x19, x20
    ldr     x2, [x9, #BlockNode_slot]
    mov     x0, x19
    bl      lantern_ancestor
    cbnz    x0, 7f
    cmp     x1, x20
    b.ne    6f
    mov     x0, x19                         /* get_proposer_score(store) */
    LDQ     x1, x19, Store_config + CONFIG_PROPOSER_SCORE_BOOST
    bl      lantern_committee_fraction
    cbnz    x0, 7f
    adds    x21, x21, x1
    b.cs    9f
6:  mov     x1, x21
    mov     x0, #LANTERN_OK
7:  LEAVE 0
8:  mov     x0, #LANTERN_INVALID_UNKNOWN_BLOCK
    LEAVE 0
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    LEAVE 0
END_FUNCTION lantern_weight

SPEC_FUNCTION get_weight
    FRAME 16
    str     x2, [sp, #16]
    NEED_BALANCES x0, 8f
    ldr     x1, [x1]
    bl      lantern_weight
    cbnz    x0, 7f
    ldr     x2, [sp, #16]
    str     x1, [x2]
7:  UNFRAME 16
8:  mov     x0, #LANTERN_NEED_JUSTIFIED_STATE
    UNFRAME 16
SPEC_END get_weight

/* ---------------------------------------------------------------- get_head */

/*
 * get_filtered_node_tree(store x0), with scratch x1 of S(1) for the node count: x0 = status,
 * x1 = the flags of each node at the end of scratch (F_VIABLE: in the tree), x2 = the justified node.
 * x19 store, x20 flags, x21 node count, x22 justified node, x23 current epoch, x24 i,
 * x26 correct_justified, x28 nodes.
 */
LOCAL_FUNCTION lantern_filter_tree
    ENTER 16
    mov     x19, x0
    LDQ     x21, x19, Store_blocks + 8
    ldr     x9, [x1]                        /* scratch: the flags at its end */
    lsl     x10, x21, #3
    add     x11, x10, #LIST_FIXED
    MOVQ    x12, LANTERN_SCRATCH_FIXED
    add     x11, x11, x12
    cmp     x9, x11
    b.lo    9f
    sub     x9, x9, x10
    add     x20, x1, x9
    LDQ     x28, x19, Store_blocks
    add     x28, x19, x28
    mov     x0, x19
    add     x1, x19, #(Store_justified_checkpoint + Checkpoint_root)
    bl      lantern_find_node
    cmn     x0, #1
    b.eq    8f
    mov     x22, x0
    STORE_SLOT x23, x19, 10f
    lsr     x23, x23, #LOG2_SLOTS_PER_EPOCH /* get_current_store_epoch(store) */
    mov     x0, x20
    lsl     x1, x21, #3
    bl      lantern_zero
    mov     x9, #F_SUBTREE                  /* the subtree of the justified node: parents come first */
    str     x9, [x20, x22, lsl #3]
    add     x24, x22, #1
1:  cmp     x24, x21
    b.hs    2f
    mov     x9, #BlockNode__mem
    madd    x10, x24, x9, x28
    ldr     x11, [x10, #BlockNode_parent]
    cmn     x11, #1
    b.eq    15f
    ldr     x12, [x10, #BlockNode_payload_status]
    cmp     x12, #PAYLOAD_STATUS_INVALIDATED    /* removed from fork choice (optimistic sync) */
    b.eq    15f
    ldr     x12, [x20, x11, lsl #3]
    tbz     x12, #0, 15f
    orr     x12, x12, #F_CHILD
    str     x12, [x20, x11, lsl #3]
    mov     x12, #F_SUBTREE
    str     x12, [x20, x24, lsl #3]
15: add     x24, x24, #1
    b       1b
2:  sub     x24, x21, #1                    /* filter_node_tree: children come before their parent */
3:  cmp     x24, x22
    b.lt    6f
    ldr     x12, [x20, x24, lsl #3]
    tbz     x12, #0, 5f
    tbz     x12, #1, 31f
    tbz     x12, #3, 5f                     /* with children: viable when a child is */
    b       4f
31: mov     x9, #BlockNode__mem             /* a leaf */
    madd    x13, x24, x9, x28
    ldr     x10, [x13, #BlockNode_slot]     /* voting_source = get_voting_source(store, node.root) */
    lsr     x10, x10, #LOG2_SLOTS_PER_EPOCH
    add     x14, x13, #BlockNode_justified_checkpoint
    add     x15, x13, #BlockNode_unrealized_justified_checkpoint
    cmp     x23, x10                        /* current_epoch > block_epoch: the pulled up source */
    csel    x14, x15, x14, hi
    ldr     x14, [x14, #Checkpoint_epoch]
    mov     x26, #1                         /* correct_justified */
    ldr     x15, [x19, #(Store_justified_checkpoint + Checkpoint_epoch)]
    cbz     x15, 34f                        /* store.justified_checkpoint.epoch == GENESIS_EPOCH */
    cmp     x14, x15
    b.eq    34f
    adds    x14, x14, #2                    /* voting_source.epoch + 2 >= current_epoch */
    b.cs    10f
    cmp     x14, x23
    b.hs    34f
    mov     x26, #0
34: mov     x0, x19                         /* finalized_checkpoint_block */
    mov     x1, x24
    ldr     x2, [x19, #(Store_finalized_checkpoint + Checkpoint_epoch)]
    bl      lantern_checkpoint_block
    cbnz    x0, 7f
    ldr     x9, [x19, #(Store_finalized_checkpoint + Checkpoint_epoch)]
    cbz     x9, 35f                         /* correct_finalized */
    NODE    x14, x19, x1
    add     x15, x19, #(Store_finalized_checkpoint + Checkpoint_root)
    NE32    x14, x15, 5f
35: cbz     x26, 5f
4:  ldr     x12, [x20, x24, lsl #3]         /* viable: so is its parent */
    orr     x12, x12, #F_VIABLE
    str     x12, [x20, x24, lsl #3]
    cmp     x24, x22
    b.eq    5f
    mov     x9, #BlockNode__mem
    madd    x13, x24, x9, x28
    ldr     x11, [x13, #BlockNode_parent]
    ldr     x12, [x20, x11, lsl #3]
    orr     x12, x12, #F_CHILD_VIABLE
    str     x12, [x20, x11, lsl #3]
5:  sub     x24, x24, #1
    b       3b
6:  mov     x1, x20
    mov     x2, x22
    mov     x0, #LANTERN_OK
7:  LEAVE 16
8:  mov     x0, #LANTERN_INVALID_UNKNOWN_BLOCK
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
10: mov     x0, #LANTERN_INVALID_OVERFLOW
    LEAVE 16
END_FUNCTION lantern_filter_tree

/*
 * The weights of all nodes at once (fork-choice.md, lantern_get_head): store x0, weights x1 and
 * flags x2, 8 bytes a node: x0 = the status of the proposer boost, LANTERN_OK or a failure of its
 * node or get_proposer_score. Each weight is get_weight of its node; a sum past 2^64 - 1 sets
 * F_OVERFLOW in the flags of the node and of each node above it. x19 store, x20 flags, x21 node
 * count, x23 the weights, x24 i, x28 nodes. Locals: L the status of the boost.
 */
LOCAL_FUNCTION lantern_weights
    ENTER 16
    mov     x19, x0
    mov     x23, x1
    mov     x20, x2
    LDQ     x21, x19, Store_blocks + 8
    LDQ     x28, x19, Store_blocks
    add     x28, x19, x28
    mov     x0, x23
    lsl     x1, x21, #3
    bl      lantern_zero
    PART    x5, x6, x19, Store_validators   /* each counted latest message, on its node */
    mov     x3, #BlockNode__mem
1:  cbz     x6, 3f
    sub     x6, x6, #1
    ldr     x8, [x5, #StoreValidator_flags]
    and     x8, x8, #(STORE_ACTIVE_UNSLASHED | STORE_EQUIVOCATING)
    cmp     x8, #STORE_ACTIVE_UNSLASHED     /* unslashed and active, not equivocating */
    b.ne    2f
    ldr     x9, [x5, #StoreValidator_latest_node]
    cmn     x9, #1
    b.eq    2f
    madd    x10, x9, x3, x28                /* not a vote for an INVALIDATED block (optimistic sync) */
    ldr     x11, [x10, #BlockNode_payload_status]
    cmp     x11, #PAYLOAD_STATUS_INVALIDATED
    b.eq    2f
    ldr     x10, [x5, #StoreValidator_effective_balance]
    ldr     x11, [x23, x9, lsl #3]
    adds    x11, x11, x10
    b.cc    11f
    ldr     x12, [x20, x9, lsl #3]
    orr     x12, x12, #F_OVERFLOW
    str     x12, [x20, x9, lsl #3]
11: str     x11, [x23, x9, lsl #3]
2:  add     x5, x5, #StoreValidator__mem
    b       1b
3:  str     xzr, [sp, #L]                   /* the proposer boost, on its node */
    add     x1, x19, #Store_proposer_boost_root
    ldp     x9, x10, [x1]
    ldp     x11, x12, [x1, #16]
    orr     x9, x9, x10
    orr     x11, x11, x12
    orr     x9, x9, x11
    cbz     x9, 4f
    mov     x0, x19
    bl      lantern_find_node
    cmn     x0, #1
    b.ne    31f
    mov     x9, #LANTERN_INVALID_UNKNOWN_BLOCK
    str     x9, [sp, #L]
    b       4f
31: mov     x24, x0
    mov     x9, #BlockNode__mem             /* no boost from an INVALIDATED block (optimistic sync) */
    madd    x9, x24, x9, x28
    ldr     x9, [x9, #BlockNode_payload_status]
    cmp     x9, #PAYLOAD_STATUS_INVALIDATED
    b.eq    4f
    mov     x0, x19                         /* get_proposer_score(store) */
    LDQ     x1, x19, Store_config + CONFIG_PROPOSER_SCORE_BOOST
    bl      lantern_committee_fraction
    cbz     x0, 32f
    str     x0, [sp, #L]
    b       4f
32: ldr     x11, [x23, x24, lsl #3]
    adds    x11, x11, x1
    b.cc    33f
    ldr     x12, [x20, x24, lsl #3]
    orr     x12, x12, #F_OVERFLOW
    str     x12, [x20, x24, lsl #3]
33: str     x11, [x23, x24, lsl #3]
4:  sub     x24, x21, #1                    /* from the last node to the first: onto the parent */
    mov     x3, #BlockNode__mem
41: cbz     x24, 60f
    madd    x10, x24, x3, x28
    ldr     x11, [x10, #BlockNode_parent]
    cmn     x11, #1
    b.eq    44f
    ldr     x12, [x23, x24, lsl #3]
    ldr     x13, [x23, x11, lsl #3]
    ldr     x14, [x20, x24, lsl #3]
    ldr     x15, [x20, x11, lsl #3]
    and     x14, x14, #F_OVERFLOW
    orr     x15, x15, x14
    adds    x13, x13, x12
    b.cc    43f
    orr     x15, x15, #F_OVERFLOW
43: str     x13, [x23, x11, lsl #3]
    str     x15, [x20, x11, lsl #3]
44: sub     x24, x24, #1
    b       41b
60: ldr     x0, [sp, #L]
    LEAVE 16
END_FUNCTION lantern_weights

/*
 * get_head(store x0) with scratch x1 of S(2) for the node count: x0 = status, x1 = the head
 * node, with the weights of weights. x19 store, x20 flags, x21 node count, x22 justified node,
 * x23 the weights, x24 i, x25 head, x26 the best child, x27 its weight, x28 nodes. Locals: L the
 * status of the boost.
 */
LOCAL_FUNCTION lantern_head
    ENTER 16
    mov     x19, x0
    LDQ     x21, x19, Store_blocks + 8
    ldr     x9, [x1]                        /* the weights: 8 bytes a node, before lantern_filter_tree's flags */
    lsl     x10, x21, #4
    add     x11, x10, #LIST_FIXED
    MOVQ    x12, LANTERN_SCRATCH_FIXED
    add     x11, x11, x12
    cmp     x9, x11
    b.lo    9f
    sub     x9, x9, x10
    add     x23, x1, x9
    mov     x0, x19
    bl      lantern_filter_tree                     /* nodes = get_filtered_node_tree(store) */
    cbnz    x0, 7f
    mov     x20, x1
    mov     x22, x2
    LDQ     x28, x19, Store_blocks
    add     x28, x19, x28
    mov     x0, x19                         /* the weights of all nodes at once */
    mov     x1, x23
    mov     x2, x20
    bl      lantern_weights
    str     x0, [sp, #L]
60: mov     x25, x22                        /* head = the justified node */
61: mov     x26, #-1                        /* the best child so far */
    mov     x27, #0
    add     x24, x25, #1
62: cmp     x24, x21
    b.hs    65f
    mov     x9, #BlockNode__mem
    madd    x13, x24, x9, x28
    ldr     x11, [x13, #BlockNode_parent]
    cmp     x11, x25
    b.ne    64f
    ldr     x12, [x20, x24, lsl #3]
    tbz     x12, #2, 64f                    /* a child in nodes */
    ldr     x0, [sp, #L]                    /* its weight: a failure of the boost, or a sum past 2^64 - 1 */
    cbnz    x0, 7f
    tst     x12, #F_OVERFLOW
    b.ne    8f
    ldr     x1, [x23, x24, lsl #3]
    cmn     x26, #1
    b.eq    63f
    cmp     x1, x27                         /* max by (weight, root) */
    b.hi    63f
    b.lo    64f
    mov     x9, #BlockNode__mem
    madd    x13, x24, x9, x28
    madd    x14, x26, x9, x28
    ROOT_GT x13, x14, 63f, 64f
63: mov     x26, x24
    mov     x27, x1
64: add     x24, x24, #1
    b       62b
65: cmn     x26, #1
    b.eq    66f
    mov     x25, x26
    b       61b
66: mov     x1, x25
    mov     x0, #LANTERN_OK
7:  LEAVE 16
8:  mov     x0, #LANTERN_INVALID_OVERFLOW
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_head

/* x19 store, x20 out. */
SPEC_FUNCTION get_filtered_node_tree
    ENTER 0
    mov     x19, x0
    mov     x20, x2
    bl      lantern_filter_tree
    cbnz    x0, 7f
    LDQ     x9, x19, Store_blocks + 8
    mov     x10, #0                         /* the nodes in the tree */
    mov     x11, #0
1:  cmp     x11, x9
    b.hs    2f
    ldr     x12, [x1, x11, lsl #3]
    tst     x12, #F_VIABLE
    cinc    x10, x10, ne
    add     x11, x11, #1
    b       1b
2:  lsl     x12, x10, #3
    add     x12, x12, #LIST_FIXED
    ldr     x13, [x20]
    cmp     x13, x12
    b.lo    9f
    mov     x12, #LIST_FIXED
    str     x12, [x20, #LIST_OFFSET]
    str     x10, [x20, #LIST_COUNT]
    add     x13, x20, #LIST_FIXED
    mov     x11, #0
3:  cmp     x11, x9
    b.hs    4f
    ldr     x12, [x1, x11, lsl #3]
    tbz     x12, #2, 31f
    str     x11, [x13], #8
31: add     x11, x11, #1
    b       3b
4:  mov     x0, #LANTERN_OK
7:  LEAVE 0
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END get_filtered_node_tree

SPEC_FUNCTION get_head
    FRAME 16
    str     x2, [sp, #16]
    NEED_BALANCES x0, 8f
    bl      lantern_head
    cbnz    x0, 7f
    ldr     x2, [sp, #16]
    str     x1, [x2]
7:  UNFRAME 16
8:  mov     x0, #LANTERN_NEED_JUSTIFIED_STATE
    UNFRAME 16
SPEC_END get_head

/* ---------------------------------------------------------------- Checkpoints and time */

/* lantern_update_checkpoints(store x0, justified x1, finalized x2). A leaf; uses x3, x16, x17. */
LOCAL_FUNCTION lantern_update_checkpoints
    UNWIND_END_PROLOGUE
    add     x3, x0, #Store_justified_checkpoint
    RAISE   x3, x1
    add     x3, x0, #Store_finalized_checkpoint
    RAISE   x3, x2
    ret
END_FUNCTION lantern_update_checkpoints

/* lantern_update_unrealized_checkpoints(store x0, justified x1, finalized x2). A leaf; uses x3, x16, x17. */
LOCAL_FUNCTION lantern_update_unrealized_checkpoints
    UNWIND_END_PROLOGUE
    add     x3, x0, #Store_unrealized_justified_checkpoint
    RAISE   x3, x1
    add     x3, x0, #Store_unrealized_finalized_checkpoint
    RAISE   x3, x2
    ret
END_FUNCTION lantern_update_unrealized_checkpoints

/* lantern_on_tick_per_slot(store x0, time_ms x1), with time_ms not before genesis_time_ms. A leaf. */
LOCAL_FUNCTION lantern_on_tick_per_slot
    UNWIND_END_PROLOGUE
    STORE_SLOT x2, x0, 9f                   /* previous_slot */
    str     x1, [x0, #Store_time_ms]
    STORE_SLOT x3, x0, 9f                   /* current_slot */
    cmp     x3, x2
    b.ls    9f
    stp     xzr, xzr, [x0, #Store_proposer_boost_root]     /* a new slot: proposer_boost_root = Root() */
    stp     xzr, xzr, [x0, #(Store_proposer_boost_root + 16)]
    tst     x3, #(SLOTS_PER_EPOCH - 1)      /* a new epoch: pull up the unrealized checkpoints */
    b.ne    9f
    add     x1, x0, #Store_unrealized_justified_checkpoint
    add     x2, x0, #Store_unrealized_finalized_checkpoint
    b       lantern_update_checkpoints
9:  ret
END_FUNCTION lantern_on_tick_per_slot

/* x19 store, x20 time_ms, x21 result, x22 tick slot, x23 genesis_time_ms, x24 SLOT_DURATION_MS. */
SPEC_FUNCTION on_tick
    ENTER 0
    mov     x19, x0
    ldr     x20, [x1]
    mov     x21, x2
    str     xzr, [x21]
    ldr     x23, [x19, #Store_genesis_time_ms]
    LDQ     x24, x19, Store_config + CONFIG_SLOT_DURATION_MS
    subs    x22, x20, x23                   /* tick_slot = compute_slot_at_time_ms(genesis_time_ms, time_ms) */
    b.lo    6f
    udiv    x22, x22, x24
1:  STORE_SLOT x9, x19, 6f                  /* catch up slot by slot */
    cmp     x9, x22
    b.hs    2f
    add     x9, x9, #1
    madd    x1, x9, x24, x23                /* compute_time_at_slot_ms(genesis_time_ms, next_slot) */
    mov     x0, x19
    bl      lantern_on_tick_per_slot
    b       1b
2:  mov     x0, x19
    mov     x1, x20
    bl      lantern_on_tick_per_slot
    mov     x0, #LANTERN_OK
    LEAVE 0
6:  mov     x9, #LANTERN_INVALID_OVERFLOW
    str     x9, [x21]
    mov     x0, #LANTERN_OK
    LEAVE 0
SPEC_END on_tick

/* ---------------------------------------------------------------- The store */

/*
 * x0 store, x1 state; x2 entries, x3 entry count, x4 validators, x5 validator count,
 * x6 epoch, x7 total, x8 i.
 */
SPEC_LEAF store_justified_checkpoint_state
    PART    x2, x3, x0, Store_validators
    PART    x4, x5, x1, BeaconState_validators
    cmp     x5, x3
    b.hi    9f
    LDQ     x6, x1, BeaconState_slot
    lsr     x6, x6, #LOG2_SLOTS_PER_EPOCH   /* get_current_epoch(state) */
    mov     x7, #0
    mov     x8, #0
    mov     x9, x4
1:  cmp     x8, x5                          /* get_total_balance of the active unslashed, before any change */
    b.hs    2f
    ACTIVE_UNSLASHED x10, x9, x6
    cbz     x10, 11f
    ldr     x11, [x9, #Validator_effective_balance]
    adds    x7, x7, x11
    b.cs    8f
11: add     x9, x9, #Validator__mem
    add     x8, x8, #1
    b       1b
2:  MOVQ    x9, EFFECTIVE_BALANCE_INCREMENT
    cmp     x7, x9
    csel    x7, x7, x9, hs
    str     x7, [x0, #Store_balances_total]
    mov     x8, #0
3:  cmp     x8, x3
    b.hs    5f
    ldr     x12, [x2, #StoreValidator_flags]
    and     x12, x12, #STORE_EQUIVOCATING
    mov     x11, #0
    cmp     x8, x5
    b.hs    4f
    ACTIVE_UNSLASHED x10, x4, x6
    orr     x12, x12, #STORE_IN_REGISTRY
    orr     x12, x12, x10
    ldr     x11, [x4, #Validator_effective_balance]
    add     x4, x4, #Validator__mem
4:  str     x11, [x2, #StoreValidator_effective_balance]
    str     x12, [x2, #StoreValidator_flags]
    add     x2, x2, #StoreValidator__mem
    add     x8, x8, #1
    b       3b
5:  add     x9, x0, #Store_balances_checkpoint
    add     x10, x0, #Store_justified_checkpoint
    COPY40  x9, x10
    RETURN_OK
8:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    ret
SPEC_END store_justified_checkpoint_state

/*
 * x19 anchor state, x20 anchor block, x21 config, x22 room, x23 scratch, x24 store,
 * x25 node capacity, x26 validator capacity, x27 anchor epoch, x28 the anchor node.
 * Locals: L state root (32), L+32 anchor root (32), L+64 size.
 */
SPEC_FUNCTION get_forkchoice_store
    ENTER 80
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    ldp     x25, x26, [x22]
    cbz     x25, 9f
    LDQ     x9, x19, BeaconState_validators + 8
    cmp     x26, x9
    b.lo    9f
    mov     x0, x22
    add     x1, sp, #(L + 64)
    CALL_GLOBAL lantern_store_size
    cbnz    x0, 9f
    ldr     x9, [sp, #(L + 64)]
    ldr     x10, [x24]
    cmp     x10, x9
    b.lo    9f
    ldr     x9, [x23]
    MOVQ    x10, LANTERN_SCRATCH_FIXED
    cmp     x9, x10
    b.lo    9f
    ADDRESS x0, lantern_type_BeaconState    /* assert anchor_block.state_root == hash_tree_root(anchor_state) */
    mov     x1, x19
    mov     x2, x23
    add     x3, sp, #L
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    add     x14, x20, #BeaconBlock_state_root
    add     x15, sp, #L
    NE32    x14, x15, 6f
    ADDRESS x0, lantern_type_BeaconBlock    /* anchor_root = hash_tree_root(anchor_block) */
    mov     x1, x20
    mov     x2, x23
    add     x3, sp, #(L + 32)
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    LDQ     x9, x19, BeaconState_genesis_time       /* genesis_time_ms = seconds_to_milliseconds(genesis_time) */
    mov     x10, #1000
    umulh   x11, x9, x10
    mul     x9, x9, x10
    cmp     x11, #0
    csinv   x9, x9, xzr, eq                 /* UINT64_MAX when it does not fit */
    LDQ     x10, x19, BeaconState_slot      /* time_ms = compute_time_at_slot_ms(genesis_time_ms, anchor_state.slot) */
    ldr     x11, [x21, #CONFIG_SLOT_DURATION_MS]
    umulh   x12, x10, x11
    cbnz    x12, 5f
    mul     x12, x10, x11
    adds    x12, x12, x9
    b.cs    5f
    str     x12, [x24, #Store_time_ms]
    str     x9, [x24, #Store_genesis_time_ms]
    lsr     x27, x10, #LOG2_SLOTS_PER_EPOCH /* anchor_epoch = get_current_epoch(anchor_state) */
    add     x10, sp, #(L + 32)              /* the four checkpoints: (anchor_epoch, anchor_root) */
    str     x27, [x24, #Store_justified_checkpoint]
    add     x9, x24, #(Store_justified_checkpoint + Checkpoint_root)
    COPY32  x9, x10
    str     x27, [x24, #Store_finalized_checkpoint]
    add     x9, x24, #(Store_finalized_checkpoint + Checkpoint_root)
    COPY32  x9, x10
    str     x27, [x24, #Store_unrealized_justified_checkpoint]
    add     x9, x24, #(Store_unrealized_justified_checkpoint + Checkpoint_root)
    COPY32  x9, x10
    str     x27, [x24, #Store_unrealized_finalized_checkpoint]
    add     x9, x24, #(Store_unrealized_finalized_checkpoint + Checkpoint_root)
    COPY32  x9, x10
    add     x9, x24, #Store_proposer_boost_root
    stp     xzr, xzr, [x9]
    stp     xzr, xzr, [x9, #16]
    MOVQ    x9, STORE_FIXED                 /* the parts: the anchor node, then the validators */
    str     x9, [x24, #Store_blocks]
    mov     x10, #1
    str     x10, [x24, #(Store_blocks + 8)]
    mov     x10, #BlockNode__mem
    madd    x10, x25, x10, x9
    str     x10, [x24, #Store_validators]
    str     x26, [x24, #(Store_validators + 8)]
    add     x0, x24, #Store_config
    mov     x1, x21
    MOVQ    x2, CONFIG_SIZE
    bl      lantern_copy
    MOVQ    x9, STORE_FIXED                 /* blocks = {anchor_root: anchor_block} */
    add     x28, x24, x9
    add     x9, sp, #(L + 32)
    COPY32  x28, x9
    add     x9, x28, #BlockNode_parent_root
    add     x10, x20, #BeaconBlock_parent_root
    COPY32  x9, x10
    ldr     x9, [x20, #BeaconBlock_slot]
    str     x9, [x28, #BlockNode_slot]
    ldr     x9, [x20, #BeaconBlock_proposer_index]
    str     x9, [x28, #BlockNode_proposer_index]
    mov     x9, #-1
    str     x9, [x28, #BlockNode_parent]
    add     x9, x28, #BlockNode_justified_checkpoint        /* block_states[anchor_root].current_justified_checkpoint */
    ADDQ    x10, x19, BeaconState_current_justified_checkpoint
    COPY40  x9, x10
    LDQ     x9, x19, BeaconState_finalized_checkpoint + Checkpoint_epoch   /* and its finalized_checkpoint.epoch */
    str     x9, [x28, #BlockNode_finalized_epoch]
    str     x27, [x28, #BlockNode_unrealized_justified_checkpoint]     /* unrealized_justifications */
    add     x9, x28, #(BlockNode_unrealized_justified_checkpoint + Checkpoint_root)
    add     x10, sp, #(L + 32)
    COPY32  x9, x10
    str     xzr, [x28, #BlockNode_timely]
.if FORK >= FORK_BELLATRIX
    LDQ     x9, x19, BeaconState_latest_execution_payload_header  /* the anchor state's payload hash, VALID */
    add     x9, x19, x9
    add     x9, x9, #ExecutionPayloadHeader_block_hash
    add     x10, x28, #BlockNode_block_hash
    COPY32  x10, x9
.else
    stp     xzr, xzr, [x28, #BlockNode_block_hash]          /* no payload before bellatrix: a zero hash */
    stp     xzr, xzr, [x28, #(BlockNode_block_hash + 16)]
.endif
    mov     x9, #PAYLOAD_STATUS_VALID
    str     x9, [x28, #BlockNode_payload_status]
    PART    x9, x10, x24, Store_validators  /* latest_messages = {} */
    mov     x11, #-1
1:  cbz     x10, 2f
    stp     xzr, x11, [x9, #StoreValidator_latest_epoch]
    stp     xzr, xzr, [x9, #StoreValidator_effective_balance]
    add     x9, x9, #StoreValidator__mem
    sub     x10, x10, #1
    b       1b
2:  mov     x0, x24                         /* checkpoint_states = {justified_checkpoint: anchor_state} */
    mov     x1, x19
    bl      lantern_store_justified_checkpoint_state
7:  LEAVE 80
5:  mov     x0, #LANTERN_INVALID_OVERFLOW
    LEAVE 80
6:  mov     x0, #LANTERN_INVALID_ANCHOR
    LEAVE 80
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
SPEC_END get_forkchoice_store

/* ---------------------------------------------------------------- Attestations */

/*
 * x0 = validate_on_attestation(store x0, data x1, is_from_block x2 as a value), as a status;
 * x1 = the node of the head vote. x19 store, x20 data, x21 target node, x22 head node.
 */
LOCAL_FUNCTION lantern_validate_attestation
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    ldr     x9, [x20, #(AttestationData_target + Checkpoint_epoch)]
    cbnz    x2, 1f
    STORE_SLOT x10, x19, 10f                /* validate_target_epoch_against_current_time */
    lsr     x10, x10, #LOG2_SLOTS_PER_EPOCH /* current_epoch */
    subs    x11, x10, #1
    csel    x11, x11, xzr, hs               /* previous_epoch = saturating_sub(current_epoch, 1) */
    cmp     x9, x10
    ccmp    x9, x11, #4, ne
    b.ne    6f
1:  ldr     x10, [x20, #AttestationData_slot]
    cmp     x9, x10, lsr #LOG2_SLOTS_PER_EPOCH      /* target.epoch == compute_epoch_at_slot(slot) */
    b.ne    6f
    mov     x0, x19                         /* target.root in store.blocks */
    add     x1, x20, #(AttestationData_target + Checkpoint_root)
    bl      lantern_find_node
    cmn     x0, #1
    b.eq    8f
    mov     x21, x0
    mov     x0, x19                         /* beacon_block_root in store.blocks */
    add     x1, x20, #AttestationData_beacon_block_root
    bl      lantern_find_node
    cmn     x0, #1
    b.eq    8f
    mov     x22, x0
    NODE    x9, x19, x22
    ldr     x9, [x9, #BlockNode_slot]
    ldr     x10, [x20, #AttestationData_slot]
    cmp     x9, x10
    b.hi    5f
    mov     x0, x19                         /* target.root == get_checkpoint_block(beacon_block_root, target.epoch) */
    mov     x1, x22
    ldr     x2, [x20, #(AttestationData_target + Checkpoint_epoch)]
    bl      lantern_checkpoint_block
    cbnz    x0, 7f
    cmp     x1, x21
    b.ne    6f
    ldr     x10, [x20, #AttestationData_slot]       /* get_current_slot(store) >= slot + 1 */
    adds    x10, x10, #1
    b.cs    10f
    STORE_SLOT x9, x19, 10f
    cmp     x9, x10
    b.lo    4f
    mov     x1, x22
    mov     x0, #LANTERN_OK
7:  LEAVE 0
4:  mov     x0, #LANTERN_INVALID_FUTURE_SLOT
    LEAVE 0
5:  mov     x0, #LANTERN_INVALID_ATTESTATION_SLOT
    LEAVE 0
6:  mov     x0, #LANTERN_INVALID_ATTESTATION_TARGET
    LEAVE 0
8:  mov     x0, #LANTERN_INVALID_UNKNOWN_BLOCK
    LEAVE 0
10: mov     x0, #LANTERN_INVALID_OVERFLOW
    LEAVE 0
END_FUNCTION lantern_validate_attestation

SPEC_FUNCTION validate_on_attestation
    FRAME 0
    add     x1, x1, #Attestation_data
    ldr     x2, [x2]
    bl      lantern_validate_attestation
    UNFRAME 0
SPEC_END validate_on_attestation

/* Local: sp+16 the start slot. */
SPEC_FUNCTION store_target_checkpoint_state
    FRAME 16
    ldr     x9, [x1, #Checkpoint_epoch]
    lsr     x10, x9, #(64 - LOG2_SLOTS_PER_EPOCH)
    cbnz    x10, 6f
    lsl     x9, x9, #LOG2_SLOTS_PER_EPOCH   /* compute_start_slot_at_epoch(target.epoch) */
    str     x9, [sp, #16]
    LDQ     x10, x0, BeaconState_slot
    cmp     x10, x9
    b.hs    5f
    add     x1, sp, #16                     /* process_slots(base_state, start slot) */
    bl      lantern_process_slots
    UNFRAME 16
5:  str     xzr, [x4]
    mov     x0, #LANTERN_OK
    UNFRAME 16
6:  mov     x9, #LANTERN_INVALID_OVERFLOW
    str     x9, [x4]
    mov     x0, #LANTERN_OK
    UNFRAME 16
SPEC_END store_target_checkpoint_state

/*
 * x19 store, x20 attestation, x21 is_from_block, x22 target state, x23 scratch, x24 result,
 * x25 scratch size for callees, x26 indexed attestation, x27 head vote node. Locals: L valid.
 */
SPEC_FUNCTION on_attestation
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    str     xzr, [x24]
    NEED_SCRATCH_B x23, x22, 8, FC_ATTEST_EXTRA, 9f
    ldr     x9, [x23]                       /* own scratch at the end: the indexed attestation */
    LDQ     x10, x22, BeaconState_validators + 8
    lsl     x10, x10, #3
    MOVQ    x11, IndexedAttestation__fixed + 8
    add     x10, x10, x11
    sub     x25, x9, x10
    add     x26, x23, x25
    str     x10, [x26]
    mov     x0, x19                         /* validate_on_attestation(store, attestation, is_from_block) */
    add     x1, x20, #Attestation_data
    ldr     x2, [x21]
    bl      lantern_validate_attestation
    cbnz    x0, 6f
    mov     x27, x1
    str     x25, [x23]                      /* get_indexed_attestation(target_state, attestation) */
    mov     x0, x22
    mov     x1, x20
    mov     x3, x23
    mov     x4, x26
    ldr     x2, [x19, #(Store_config + CONFIG_COMMITTEE_CACHE)]
    bl      lantern_get_indexed_attestation
    CHECK_STATUS x24, 7f, 8f
    str     x25, [x23]                      /* assert is_valid_indexed_attestation(target_state, indexed_attestation) */
    mov     x0, x22
    mov     x1, x26
    mov     x3, x23
    add     x4, sp, #L
    ldr     x2, [x19, #(Store_config + CONFIG_PUBKEY_CACHE)]
    mov     x5, x20                         /* with the attestation and its CommitteeCache: key sums */
    ldr     x6, [x19, #(Store_config + CONFIG_COMMITTEE_CACHE)]
    bl      lantern_indexed_attestation_valid
    CHECK_STATUS x24, 7f, 8f
    ldr     x9, [sp, #L]
    mov     x0, #LANTERN_INVALID_ATTESTATION
    cbz     x9, 6f
    PART    x9, x10, x26, IndexedAttestation_attesting_indices      /* update_latest_messages */
    PART    x11, x12, x19, Store_validators
    cbz     x10, 8f
    sub     x13, x10, #1                    /* the indices ascend: the last needs an entry */
    ldr     x13, [x9, x13, lsl #3]
    cmp     x13, x12
    b.hs    9f
    ldr     x14, [x20, #(Attestation_data + AttestationData_target + Checkpoint_epoch)]
1:  cbz     x10, 8f
    ldr     x13, [x9], #8
    add     x13, x11, x13, lsl #5
    ldr     x15, [x13, #StoreValidator_flags]
    tbnz    x15, #1, 2f                     /* in store.equivocating_indices */
    ldp     x15, x12, [x13]                 /* latest epoch and node */
    cmn     x12, #1
    b.eq    3f
    cmp     x14, x15                        /* target.epoch > latest_messages[i].epoch */
    b.ls    2f
3:  stp     x14, x27, [x13]
2:  sub     x10, x10, #1
    b       1b
8:  mov     x0, #LANTERN_OK
7:  LEAVE 16
6:  str     x0, [x24]
    mov     x0, #LANTERN_OK
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END on_attestation

/*
 * x19 store, x20 attester slashing, x21 state, x22 scratch, x23 result, x24 attestation_1,
 * x25 attestation_2, x26 scratch size. Locals: L out.
 */
SPEC_FUNCTION on_attester_slashing
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    str     xzr, [x23]
    NEED_SCRATCH x22, x21, 7, 9f
    ldr     x26, [x22]
    PART    x24, x9, x20, AttesterSlashing_attestation_1
    PART    x25, x9, x20, AttesterSlashing_attestation_2
    add     x0, x24, #IndexedAttestation_data       /* assert is_slashable_attestation_data(...) */
    add     x1, x25, #IndexedAttestation_data
    add     x2, sp, #L
    bl      lantern_is_slashable_attestation_data
    ldr     x9, [sp, #L]
    cbz     x9, 6f
    mov     x0, x21                         /* assert is_valid_indexed_attestation(state, attestation_1) */
    mov     x1, x24
    mov     x3, x22
    add     x4, sp, #L
    ldr     x2, [x19, #(Store_config + CONFIG_PUBKEY_CACHE)]
    bl      lantern_is_valid_indexed_attestation
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    7f
    cbnz    x0, 6f
    ldr     x9, [sp, #L]
    cbz     x9, 6f
    str     x26, [x22]                      /* and attestation_2 */
    mov     x0, x21
    mov     x1, x25
    mov     x3, x22
    add     x4, sp, #L
    ldr     x2, [x19, #(Store_config + CONFIG_PUBKEY_CACHE)]
    bl      lantern_is_valid_indexed_attestation
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    7f
    cbnz    x0, 6f
    ldr     x9, [sp, #L]
    cbz     x9, 6f
    PART    x13, x14, x19, Store_validators /* the common indices: both lists ascend */
    PART    x9, x10, x24, IndexedAttestation_attesting_indices
    PART    x11, x12, x25, IndexedAttestation_attesting_indices
1:  cbz     x10, 3f                         /* first, every common index needs an entry */
    cbz     x12, 3f
    ldr     x2, [x9]
    ldr     x3, [x11]
    cmp     x2, x3
    b.lo    11f
    b.hi    12f
    cmp     x2, x14
    b.hs    9f
    add     x9, x9, #8
    sub     x10, x10, #1
12: add     x11, x11, #8
    sub     x12, x12, #1
    b       1b
11: add     x9, x9, #8
    sub     x10, x10, #1
    b       1b
3:  PART    x9, x10, x24, IndexedAttestation_attesting_indices      /* then equivocating_indices.add(index) */
    PART    x11, x12, x25, IndexedAttestation_attesting_indices
4:  cbz     x10, 8f
    cbz     x12, 8f
    ldr     x2, [x9]
    ldr     x3, [x11]
    cmp     x2, x3
    b.lo    41f
    b.hi    42f
    add     x4, x13, x2, lsl #5
    ldr     x5, [x4, #StoreValidator_flags]
    orr     x5, x5, #STORE_EQUIVOCATING
    str     x5, [x4, #StoreValidator_flags]
    add     x9, x9, #8
    sub     x10, x10, #1
42: add     x11, x11, #8
    sub     x12, x12, #1
    b       4b
41: add     x9, x9, #8
    sub     x10, x10, #1
    b       4b
8:  mov     x0, #LANTERN_OK
7:  LEAVE 16
6:  mov     x9, #LANTERN_INVALID_ATTESTER_SLASHING
    str     x9, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END on_attester_slashing

/* ---------------------------------------------------------------- get_proposer_head */

/*
 * x19 store, x20 head node, x21 slot, x22 head state, x23 scratch, x24 out, x25 parent node,
 * x26 the conditions, x27 scratch size, x28 head weight.
 * Locals: L committee count, L+8 index, L+16 epoch, L+24 committee, L+32 reorg threshold.
 * Condition bits: 1 head_late, 2 ffg_competitive, 4 finalization_ok, 8 proposing_on_time,
 * 16 single_slot_reorg, 32 head_weak, 64 parent_strong, 128 current_time_ok, 256 proposer_equivocation.
 */
SPEC_FUNCTION get_proposer_head
    ENTER 48
    mov     x19, x0
    ldr     x20, [x1]
    ldr     x21, [x2]
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    NEED_BALANCES x19, 4f
    NEED_SCRATCH x23, x22, 3, 9f
    ldr     x27, [x23]
    NODE    x9, x19, x20                    /* head_block */
    ldr     x25, [x9, #BlockNode_parent]    /* parent_block = store.blocks[parent_root] */
    cmn     x25, #1
    b.eq    8f
    NODE    x8, x19, x25
    ldr     x10, [x9, #BlockNode_timely]    /* head_late = is_head_late(store, head_node.root) */
    cmp     x10, #0
    cset    x26, eq
    add     x14, x9, #BlockNode_unrealized_justified_checkpoint    /* ffg_competitive */
    add     x15, x8, #BlockNode_unrealized_justified_checkpoint
    NE40    x14, x15, 1f
    orr     x26, x26, #2
1:  lsr     x10, x21, #LOG2_SLOTS_PER_EPOCH /* finalization_ok = is_finalization_ok(store, slot) */
    ldr     x11, [x19, #(Store_finalized_checkpoint + Checkpoint_epoch)]
    subs    x10, x10, x11
    b.lo    10f
    LDQ     x11, x19, Store_config + CONFIG_REORG_MAX_EPOCHS_SINCE_FINALIZATION
    cmp     x10, x11
    b.hi    2f
    orr     x26, x26, #4
2:  STORE_SLOT x10, x19, 10f                /* proposing_on_time: get_time_into_slot_ms(store) <= cutoff */
    LDQ     x11, x19, Store_config + CONFIG_SLOT_DURATION_MS
    ldr     x12, [x19, #Store_genesis_time_ms]
    madd    x10, x10, x11, x12
    ldr     x12, [x19, #Store_time_ms]
    sub     x10, x12, x10
    LDQ     x12, x19, Store_config + CONFIG_PROPOSER_REORG_CUTOFF_BPS
    umulh   x13, x12, x11
    cbnz    x13, 10f
    mul     x12, x12, x11
    mov     x13, #BASIS_POINTS
    udiv    x12, x12, x13                   /* get_proposer_reorg_cutoff_ms() */
    cmp     x10, x12
    b.hi    3f
    orr     x26, x26, #8
3:  ldr     x10, [x8, #BlockNode_slot]      /* parent_slot_ok = parent_block.slot + 1 == head_block.slot */
    adds    x10, x10, #1
    b.cs    10f
    ldr     x11, [x9, #BlockNode_slot]
    cmp     x10, x11
    cset    x12, eq
    adds    x13, x11, #1                    /* current_time_ok = head_block.slot + 1 == slot */
    b.cs    10f
    cmp     x13, x21
    cset    x13, eq
    orr     x26, x26, x13, lsl #7
    and     x12, x12, x13
    orr     x26, x26, x12, lsl #4           /* single_slot_reorg */
    add     x14, x19, #Store_proposer_boost_root    /* assert store.proposer_boost_root != head_node.root */
    NE32    x14, x9, 31f
    mov     x0, #LANTERN_INVALID_PROPOSER_BOOST
    b       7f
31: mov     x0, x19                         /* is_head_weak: reorg_threshold */
    LDQ     x1, x19, Store_config + CONFIG_REORG_HEAD_WEIGHT_THRESHOLD
    bl      lantern_committee_fraction
    cbnz    x0, 7f
    str     x1, [sp, #(L + 32)]
    mov     x0, x19                         /* head_weight = get_attestation_score(store, head_node, justified_state) */
    mov     x1, x20
    bl      lantern_attestation_score
    cbnz    x0, 7f
    mov     x28, x1
    NODE    x9, x19, x20
    ldr     x9, [x9, #BlockNode_slot]
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH
    str     x9, [sp, #(L + 16)]
    mov     x0, x22                         /* get_committee_count_per_slot(head_state, epoch) */
    add     x1, sp, #(L + 16)
    mov     x3, x23
    add     x4, sp, #L
    ldr     x2, [x19, #(Store_config + CONFIG_COMMITTEE_CACHE)]
    bl      lantern_get_committee_count_per_slot
    cbnz    x0, 7f
    str     xzr, [sp, #(L + 8)]
5:  ldr     x9, [sp, #(L + 8)]
    ldr     x10, [sp, #L]
    cmp     x9, x10
    b.hs    6f
    LDQ     x9, x22, BeaconState_validators + 8
    SCRATCH_LIST x10, x23, x27, 0, x9       /* the committee, at the end of scratch */
    str     x10, [sp, #(L + 24)]
    SCRATCH_GIVE x23, x27, 1, x9
    mov     x0, x22                         /* get_beacon_committee(head_state, head_block.slot, index) */
    NODE    x1, x19, x20
    add     x1, x1, #BlockNode_slot
    add     x2, sp, #(L + 8)
    mov     x4, x23
    ldr     x5, [sp, #(L + 24)]
    ldr     x3, [x19, #(Store_config + CONFIG_COMMITTEE_CACHE)]
    bl      lantern_get_beacon_committee
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 24)]
    ldr     x10, [x9, #LIST_COUNT]
    add     x11, x9, #LIST_FIXED
    PART    x12, x13, x19, Store_validators
51: cbz     x10, 52f                        /* the equivocating members' effective balances */
    ldr     x14, [x11], #8
    sub     x10, x10, #1
    cmp     x14, x13
    b.hs    51b
    add     x15, x12, x14, lsl #5
    ldr     x16, [x15, #StoreValidator_flags]
    tbz     x16, #1, 51b
    tbz     x16, #2, 11f                    /* justified_state.validators[index] does not exist */
    ldr     x16, [x15, #StoreValidator_effective_balance]
    adds    x28, x28, x16
    b.cs    10f
    b       51b
52: ldr     x9, [sp, #(L + 8)]
    add     x9, x9, #1
    str     x9, [sp, #(L + 8)]
    b       5b
6:  ldr     x9, [sp, #(L + 32)]             /* head_weak = head_weight < reorg_threshold */
    cmp     x28, x9
    b.hs    61f
    orr     x26, x26, #32
61: mov     x0, x19                         /* is_parent_strong */
    LDQ     x1, x19, Store_config + CONFIG_REORG_PARENT_WEIGHT_THRESHOLD
    bl      lantern_committee_fraction
    cbnz    x0, 7f
    mov     x28, x1
    mov     x0, x19
    mov     x1, x25
    bl      lantern_attestation_score
    cbnz    x0, 7f
    cmp     x1, x28
    b.ls    62f
    orr     x26, x26, #64
62: NODE    x9, x19, x20                    /* is_proposer_equivocation */
    ldr     x10, [x9, #BlockNode_proposer_index]
    ldr     x11, [x9, #BlockNode_slot]
    PART    x12, x13, x19, Store_blocks
    mov     x14, #0
63: cbz     x13, 64f
    ldr     x15, [x12, #BlockNode_proposer_index]
    ldr     x16, [x12, #BlockNode_slot]
    cmp     x15, x10
    ccmp    x16, x11, #0, eq
    cinc    x14, x14, eq
    add     x12, x12, #BlockNode__mem
    sub     x13, x13, #1
    b       63b
64: cmp     x14, #1
    b.ls    65f
    orr     x26, x26, #256
65:
.if FORK >= FORK_FULU
    orr     x26, x26, #512                  /* fulu drops the shuffling_stable condition */
.else
    tst     x21, #(SLOTS_PER_EPOCH - 1)     /* shuffling_stable = is_shuffling_stable(slot): slot % SLOTS_PER_EPOCH != 0 */
    b.eq    651f
    orr     x26, x26, #512
651:
.endif
    mov     x9, #(1 | 2 | 4 | 8 | 16 | 32 | 64 | 512)
    and     x10, x26, x9
    cmp     x10, x9
    b.eq    66f
    mov     x9, #(32 | 128 | 256)           /* head_weak, current_time_ok and proposer_equivocation */
    and     x10, x26, x9
    cmp     x10, x9
    b.eq    66f
    str     x20, [x24]
    b       67f
66: str     x25, [x24]                      /* the parent node */
67: mov     x0, #LANTERN_OK
7:  LEAVE 48
4:  mov     x0, #LANTERN_NEED_JUSTIFIED_STATE
    LEAVE 48
8:  mov     x0, #LANTERN_INVALID_UNKNOWN_BLOCK
    LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
10: mov     x0, #LANTERN_INVALID_OVERFLOW
    LEAVE 48
11: mov     x0, #LANTERN_INVALID_VALIDATOR_INDEX
    LEAVE 48
SPEC_END get_proposer_head

/* ---------------------------------------------------------------- The merge block */

.if FORK == FORK_BELLATRIX
/* x0 = 1 when the Uint256 at x0 is below the one at x1, else 0. A leaf; uses x2-x4. */
LOCAL_FUNCTION lantern_u256_lo
    UNWIND_END_PROLOGUE
    mov     x4, #24                         /* from the most significant u64 down */
1:  ldr     x2, [x0, x4]
    ldr     x3, [x1, x4]
    cmp     x2, x3
    b.lo    2f
    b.hi    3f
    subs    x4, x4, #8
    b.hs    1b
3:  mov     x0, #0
    ret
2:  mov     x0, #1
    ret
END_FUNCTION lantern_u256_lo

/* (block, parent, config, out). Locals: sp+16 block, parent, config, out; sp+48 the first condition. */
SPEC_FUNCTION is_valid_terminal_pow_block
    FRAME 48
    stp     x0, x1, [sp, #16]
    stp     x2, x3, [sp, #32]
    add     x0, x0, #PowBlock_total_difficulty  /* is_total_difficulty_reached = block.total_difficulty >= TERMINAL_TOTAL_DIFFICULTY */
    add     x1, x2, #CONFIG_TERMINAL_TOTAL_DIFFICULTY
    bl      lantern_u256_lo
    eor     x9, x0, #1
    str     x9, [sp, #48]
    ldr     x0, [sp, #24]                   /* is_parent_total_difficulty_valid = parent.total_difficulty < TERMINAL_TOTAL_DIFFICULTY */
    add     x0, x0, #PowBlock_total_difficulty
    ldr     x1, [sp, #32]
    add     x1, x1, #CONFIG_TERMINAL_TOTAL_DIFFICULTY
    bl      lantern_u256_lo
    ldr     x9, [sp, #48]
    and     x9, x9, x0
    ldr     x3, [sp, #40]
    str     x9, [x3]
    mov     x0, #LANTERN_OK
    UNFRAME 48
SPEC_END is_valid_terminal_pow_block

/* x19 block, x20 pow_block, x21 pow_parent, x22 config, x23 payload. Locals: L valid. */
SPEC_FUNCTION validate_merge_block
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    PART    x9, x10, x19, BeaconBlock_body
    PART    x23, x10, x9, BeaconBlockBody_execution_payload
    add     x9, x22, #CONFIG_TERMINAL_BLOCK_HASH    /* TERMINAL_BLOCK_HASH != Hash32(): the override */
    ldp     x10, x11, [x9]
    ldp     x12, x13, [x9, #16]
    orr     x10, x10, x11
    orr     x12, x12, x13
    orr     x10, x10, x12
    cbz     x10, 1f
    ldr     x10, [x19, #BeaconBlock_slot]   /* assert compute_epoch_at_slot(block.slot) >= TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH */
    lsr     x10, x10, #LOG2_SLOTS_PER_EPOCH
    LDQ     x11, x22, CONFIG_TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH
    cmp     x10, x11
    b.lo    6f
    add     x14, x23, #ExecutionPayload_parent_hash     /* assert payload.parent_hash == TERMINAL_BLOCK_HASH */
    NE32    x14, x9, 6f
    b       8f
1:  cbz     x20, 6f                         /* assert pow_block is not None: get_pow_block(payload.parent_hash) */
    add     x14, x23, #ExecutionPayload_parent_hash
    add     x15, x20, #PowBlock_block_hash
    NE32    x14, x15, 6f
    cbz     x21, 6f                         /* assert pow_parent is not None: get_pow_block(pow_block.parent_hash) */
    add     x14, x20, #PowBlock_parent_hash
    add     x15, x21, #PowBlock_block_hash
    NE32    x14, x15, 6f
    mov     x0, x20                         /* assert is_valid_terminal_pow_block(pow_block, pow_parent) */
    mov     x1, x21
    mov     x2, x22
    add     x3, sp, #L
    bl      lantern_is_valid_terminal_pow_block
    ldr     x9, [sp, #L]
    cbz     x9, 6f
8:  mov     x0, #LANTERN_OK
    LEAVE 16
6:  mov     x0, #LANTERN_INVALID_MERGE_BLOCK
    LEAVE 16
SPEC_END validate_merge_block
.endif

/* ---------------------------------------------------------------- on_block */

/*
 * x19 store, x20 signed block, x21 state, x22 options, x23 scratch, x24 result, x25 block,
 * x26 scratch size, x27 parent node, x28 dependent slot, then the new node.
 * Locals: L block root (32), L+32 transition options (24, then L+48 the head), L+56 current slot,
 * L+64 pulled up justified (40), L+104 pulled up finalized (40), L+144 saved justification bits,
 * L+152 saved previous justified (40), L+192 saved current justified (40), L+232 saved finalized (40),
 * L+272 its result, L+280 timely, L+288 head dependent node, then the boost, L+296 bellatrix: is_merge_transition_block.
 */
SPEC_FUNCTION on_block
    ENTER 304
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    str     xzr, [x24]
    PART    x25, x9, x20, SignedBeaconBlock_message
    ldr     x26, [x23]
    ADDRESS x0, lantern_type_BeaconBlock    /* block_root = hash_tree_root(block) */
    mov     x1, x25
    mov     x2, x23
    add     x3, sp, #L
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    mov     x0, x19                         /* return early if the block is already known */
    add     x1, sp, #L
    bl      lantern_find_node
    cmn     x0, #1
    b.ne    8f
    mov     x0, x19                         /* assert block.parent_root in store.block_states */
    add     x1, x25, #BeaconBlock_parent_root
    bl      lantern_find_node
    mov     x27, x0
    cmn     x27, #1
    mov     x0, #LANTERN_INVALID_UNKNOWN_BLOCK
    b.eq    6f
    NODE    x9, x19, x27                    /* the parent's payload is not INVALIDATED (optimistic sync) */
    ldr     x9, [x9, #BlockNode_payload_status]
    cmp     x9, #PAYLOAD_STATUS_INVALIDATED
    mov     x0, #LANTERN_INVALID_PARENT_PAYLOAD
    b.eq    6f
    STORE_SLOT x9, x19, 5f                  /* assert get_current_slot(store) >= block.slot */
    str     x9, [sp, #(L + 56)]
    ldr     x10, [x25, #BeaconBlock_slot]
    cmp     x9, x10
    mov     x0, #LANTERN_INVALID_FUTURE_SLOT
    b.lo    6f
    ldr     x9, [x19, #(Store_finalized_checkpoint + Checkpoint_epoch)]
    lsr     x11, x9, #(64 - LOG2_SLOTS_PER_EPOCH)
    cbnz    x11, 5f
    lsl     x11, x9, #LOG2_SLOTS_PER_EPOCH  /* assert block.slot > finalized_slot */
    cmp     x10, x11
    mov     x0, #LANTERN_INVALID_NOT_FINALIZED
    b.ls    6f
    mov     x0, x19                         /* finalized_checkpoint_block of the parent */
    mov     x1, x27
    mov     x2, x9
    bl      lantern_checkpoint_block
    cbnz    x0, 6f
    NODE    x14, x19, x1
    add     x15, x19, #(Store_finalized_checkpoint + Checkpoint_root)
    mov     x0, #LANTERN_INVALID_NOT_FINALIZED
    NE32    x14, x15, 6f
.if FORK >= FORK_DENEB
    ldr     x9, [x22, #BlockOptions_data_available]     /* assert is_data_available(block_root) */
    mov     x0, #LANTERN_INVALID_DATA_UNAVAILABLE
    cbz     x9, 6f
.endif
    LDQ     x9, x19, Store_blocks + 8       /* before the state changes: room for the node */
    LDQ     x10, x19, Store_blocks
    LDQ     x11, x19, Store_validators
    sub     x11, x11, x10
    mov     x12, #BlockNode__mem
    udiv    x11, x11, x12
    cmp     x9, x11
    b.hs    9f
    NEED_BALANCES x19, 4f                   /* the justified checkpoint state, for get_head */
    lsl     x9, x9, #3                      /* scratch for get_head */
    add     x9, x9, #LIST_FIXED
    MOVQ    x10, LANTERN_SCRATCH_FIXED
    add     x9, x9, x10
    cmp     x26, x9
    b.lo    9f
.if FORK == FORK_BELLATRIX
    mov     x0, x21                         /* is_merge_transition_block(pre_state, block.body), before the state changes */
    PART    x1, x9, x25, BeaconBlock_body
    add     x2, sp, #(L + 296)
    bl      lantern_is_merge_transition_block
.endif
    mov     x9, #1                          /* state_transition(state, signed_block, validate_result=True) */
    ldr     x10, [x22, #BlockOptions_payload_status]
    cmp     x10, #PAYLOAD_STATUS_INVALIDATED
    cset    x10, ne                         /* execution_valid: VALID or NOT_VALIDATED */
    stp     x9, x10, [sp, #(L + 32)]
    ldr     x9, [x22, #BlockOptions_slots_done]
    str     x9, [sp, #(L + 48)]
    mov     x0, x21
    mov     x1, x20
    add     x2, sp, #(L + 32)
    add     x3, x19, #Store_config
    mov     x4, x23
    mov     x5, x24
    bl      lantern_state_transition
    cbnz    x0, 7f
    ldr     x9, [x24]
    cbnz    x9, 8f
.if FORK == FORK_BELLATRIX
    ldr     x9, [sp, #(L + 296)]            /* if is_merge_transition_block(pre_state, block.body): validate_merge_block(block) */
    cbz     x9, 1f
    mov     x0, x25
    ldr     x1, [x22, #BlockOptions_pow_block]
    ldr     x2, [x22, #BlockOptions_pow_parent]
    add     x3, x19, #Store_config
    bl      lantern_validate_merge_block
    cbnz    x0, 6f
1:
.endif
    str     x26, [x23]                      /* head = get_head(store), before the block is added */
    mov     x0, x19
    mov     x1, x23
    bl      lantern_head
    cbnz    x0, 6f
    str     x1, [sp, #(L + 48)]
    ADDQ    x14, x21, BeaconState_justification_bits    /* compute_pulled_up_tip: on a copy of the fields it changes */
    ldrb    w9, [x14]
    str     x9, [sp, #(L + 144)]
    ADDQ    x14, x21, BeaconState_previous_justified_checkpoint
    add     x15, sp, #(L + 152)
    COPY40  x15, x14
    ADDQ    x14, x21, BeaconState_current_justified_checkpoint
    add     x15, sp, #(L + 192)
    COPY40  x15, x14
    ADDQ    x14, x21, BeaconState_finalized_checkpoint
    add     x15, sp, #(L + 232)
    COPY40  x15, x14
    str     x26, [x23]
    mov     x0, x21                         /* process_justification_and_finalization(state) */
    add     x1, x19, #Store_config
    mov     x2, x23
    add     x3, sp, #(L + 272)
    bl      lantern_process_justification_and_finalization
    mov     x28, x0
    ADDQ    x14, x21, BeaconState_current_justified_checkpoint
    add     x15, sp, #(L + 64)
    COPY40  x15, x14
    ADDQ    x14, x21, BeaconState_finalized_checkpoint
    add     x15, sp, #(L + 104)
    COPY40  x15, x14
    ldr     x9, [sp, #(L + 144)]            /* the post-state again */
    ADDQ    x14, x21, BeaconState_justification_bits
    strb    w9, [x14]
    ADDQ    x14, x21, BeaconState_previous_justified_checkpoint
    add     x15, sp, #(L + 152)
    COPY40  x14, x15
    ADDQ    x14, x21, BeaconState_current_justified_checkpoint
    add     x15, sp, #(L + 192)
    COPY40  x14, x15
    ADDQ    x14, x21, BeaconState_finalized_checkpoint
    add     x15, sp, #(L + 232)
    COPY40  x14, x15
    mov     x0, x28
    cbnz    x0, 7f
    ldr     x0, [sp, #(L + 272)]
    cbnz    x0, 6f
    ldr     x9, [sp, #(L + 56)]             /* record_block_timeliness */
    LDQ     x10, x19, Store_config + CONFIG_SLOT_DURATION_MS
    ldr     x11, [x19, #Store_genesis_time_ms]
    madd    x12, x9, x10, x11
    ldr     x13, [x19, #Store_time_ms]
    sub     x12, x13, x12                   /* time_into_slot_ms */
    LDQ     x13, x19, Store_config + CONFIG_ATTESTATION_DUE_BPS
    umulh   x14, x13, x10
    cbnz    x14, 5f
    mul     x13, x13, x10
    mov     x14, #BASIS_POINTS
    udiv    x13, x13, x14                   /* get_attestation_due_ms() */
    cmp     x12, x13
    cset    x14, lo                         /* is_before_attesting_interval */
    ldr     x15, [x25, #BeaconBlock_slot]
    cmp     x9, x15
    csel    x14, x14, xzr, eq               /* is_timely */
    str     x14, [sp, #(L + 280)]
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH   /* update_proposer_boost_root: the dependent slot of the current epoch */
    subs    x9, x9, #MIN_SEED_LOOKAHEAD
    csel    x9, x9, xzr, hs
    lsl     x9, x9, #LOG2_SLOTS_PER_EPOCH
    subs    x9, x9, #1
    csel    x28, x9, xzr, hs
    mov     x0, x19                         /* head_dependent_root */
    ldr     x1, [sp, #(L + 48)]
    mov     x2, x28
    bl      lantern_ancestor
    cbnz    x0, 6f
    str     x1, [sp, #(L + 288)]
    LDQ     x10, x19, Store_blocks + 8      /* block_dependent_root: the new node, or an ancestor of its parent */
    ldr     x9, [x25, #BeaconBlock_slot]
    cmp     x9, x28
    b.ls    41f
    mov     x0, x19
    mov     x1, x27
    mov     x2, x28
    bl      lantern_ancestor
    cbnz    x0, 6f
    mov     x10, x1
41: ldr     x9, [sp, #(L + 288)]
    cmp     x9, x10
    cset    x9, eq                          /* is_same_dependent_root */
    ldr     x10, [sp, #(L + 280)]
    and     x9, x9, x10
    add     x14, x19, #Store_proposer_boost_root    /* is_first_block */
    ldp     x10, x11, [x14]
    ldp     x12, x13, [x14, #16]
    orr     x10, x10, x11
    orr     x12, x12, x13
    orr     x10, x10, x12
    cmp     x10, #0
    csel    x9, x9, xzr, eq
    str     x9, [sp, #(L + 288)]
    LDQ     x9, x19, Store_blocks + 8       /* every check holds: the writes, in spec order */
    add     x10, x9, #1
    STQ     x10, x19, Store_blocks + 8
    NODE    x28, x19, x9                    /* store.blocks[block_root] = block */
    add     x9, sp, #L
    COPY32  x28, x9
    add     x9, x28, #BlockNode_parent_root
    add     x10, x25, #BeaconBlock_parent_root
    COPY32  x9, x10
    ldr     x9, [x25, #BeaconBlock_slot]
    str     x9, [x28, #BlockNode_slot]
    ldr     x9, [x25, #BeaconBlock_proposer_index]
    str     x9, [x28, #BlockNode_proposer_index]
    str     x27, [x28, #BlockNode_parent]
    add     x9, x28, #BlockNode_justified_checkpoint    /* block_states[block_root].current_justified_checkpoint */
    ADDQ    x10, x21, BeaconState_current_justified_checkpoint
    COPY40  x9, x10
    LDQ     x9, x21, BeaconState_finalized_checkpoint + Checkpoint_epoch   /* and its finalized_checkpoint.epoch */
    str     x9, [x28, #BlockNode_finalized_epoch]
    add     x9, x28, #BlockNode_unrealized_justified_checkpoint     /* unrealized_justifications[block_root] */
    add     x10, sp, #(L + 64)
    COPY40  x9, x10
    ldr     x9, [sp, #(L + 280)]            /* block_timeliness[block_root] */
    str     x9, [x28, #BlockNode_timely]
.if FORK >= FORK_BELLATRIX
    PART    x9, x10, x25, BeaconBlock_body  /* the payload's hash and status */
    PART    x11, x10, x9, BeaconBlockBody_execution_payload
    add     x9, x11, #ExecutionPayload_block_hash
    add     x10, x28, #BlockNode_block_hash
    COPY32  x10, x9
.else
    stp     xzr, xzr, [x28, #BlockNode_block_hash]          /* no payload before bellatrix: a zero hash */
    stp     xzr, xzr, [x28, #(BlockNode_block_hash + 16)]
.endif
    ldr     x9, [x22, #BlockOptions_payload_status]
    str     x9, [x28, #BlockNode_payload_status]
    cbnz    x9, 44f                         /* VALID: so are its NOT_VALIDATED ancestors */
    mov     x10, x27
43: cmn     x10, #1
    b.eq    44f
    NODE    x11, x19, x10
    ldr     x12, [x11, #BlockNode_payload_status]
    cmp     x12, #PAYLOAD_STATUS_NOT_VALIDATED
    b.ne    44f
    str     xzr, [x11, #BlockNode_payload_status]
    ldr     x10, [x11, #BlockNode_parent]
    b       43b
44:
    ldr     x9, [sp, #(L + 288)]            /* proposer_boost_root = block_root */
    cbz     x9, 42f
    add     x9, x19, #Store_proposer_boost_root
    add     x10, sp, #L
    COPY32  x9, x10
42: mov     x0, x19                         /* lantern_update_checkpoints(store, state.current_justified, state.finalized) */
    ADDQ    x1, x21, BeaconState_current_justified_checkpoint
    ADDQ    x2, x21, BeaconState_finalized_checkpoint
    bl      lantern_update_checkpoints
    mov     x0, x19                         /* compute_pulled_up_tip */
    add     x1, sp, #(L + 64)
    add     x2, sp, #(L + 104)
    bl      lantern_update_unrealized_checkpoints
    ldr     x9, [x25, #BeaconBlock_slot]
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH
    ldr     x10, [sp, #(L + 56)]
    lsr     x10, x10, #LOG2_SLOTS_PER_EPOCH
    cmp     x9, x10                         /* a block from a prior epoch: the realized values */
    b.hs    8f
    mov     x0, x19
    add     x1, sp, #(L + 64)
    add     x2, sp, #(L + 104)
    bl      lantern_update_checkpoints
8:  mov     x0, #LANTERN_OK
7:  LEAVE 304
6:  str     x0, [x24]
    mov     x0, #LANTERN_OK
    LEAVE 304
5:  mov     x0, #LANTERN_INVALID_OVERFLOW
    b       6b
4:  mov     x0, #LANTERN_NEED_JUSTIFIED_STATE
    LEAVE 304
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 304
SPEC_END on_block

/* ---------------------------------------------------------------- Data availability */

.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
/*
 * (blob_kzg_commitments, blobs, proofs, settings, scratch, out): verify_blob_kzg_proof_batch of the blobs
 * and proofs that retrieve_blobs_and_proofs gave. Locals: sp+16 out.
 */
SPEC_FUNCTION is_data_available
    FRAME 16
    str     x5, [sp, #16]
    mov     x9, x0
    mov     x10, x2
    mov     x0, x3                          /* asm-crypto: settings, blobs, commitments, proofs, scratch, valid */
    mov     x2, x9
    mov     x3, x10
    CALL_GLOBAL crypto_kzg_verify_blob_kzg_proof_batch
    cmp     x0, #CRYPTO_BUFFER_TOO_SMALL
    b.eq    9f
    cbz     x0, 8f
    ldr     x9, [sp, #16]                   /* a KZG input that fails its checks: the spec's exception, not available */
    str     xzr, [x9]
8:  mov     x0, #LANTERN_OK
    UNFRAME 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    UNFRAME 16
SPEC_END is_data_available
.endif

.if FORK >= FORK_FULU

/* x19 sidecar, x20 config, x21 out. Locals: L epoch, L+8 blob parameters (16). */
SPEC_FUNCTION verify_data_column_sidecar
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    str     xzr, [x21]
    ldr     x9, [x19, #DataColumnSidecar_index]     /* sidecar.index < NUMBER_OF_COLUMNS */
    cmp     x9, #NUMBER_OF_COLUMNS
    b.hs    8f
    LDQ     x9, x19, DataColumnSidecar_kzg_commitments + 8
    cbz     x9, 8f                          /* a sidecar for zero blobs is invalid */
    LDQ     x10, x19, DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_slot
    lsr     x10, x10, #LOG2_SLOTS_PER_EPOCH
    str     x10, [sp, #L]
    add     x0, sp, #L                      /* get_blob_parameters(epoch).max_blobs_per_block */
    mov     x1, x20
    add     x2, sp, #(L + 8)
    bl      lantern_get_blob_parameters
    LDQ     x9, x19, DataColumnSidecar_kzg_commitments + 8
    ldr     x10, [sp, #(L + 16)]
    cmp     x9, x10
    b.hi    8f
    LDQ     x10, x19, DataColumnSidecar_column + 8
    cmp     x10, x9
    b.ne    8f
    LDQ     x10, x19, DataColumnSidecar_kzg_proofs + 8
    cmp     x10, x9
    b.ne    8f
    mov     x9, #1
    str     x9, [x21]
8:  mov     x0, #LANTERN_OK
    LEAVE 32
SPEC_END verify_data_column_sidecar

/* A list of x23 entries of stride bytes at the end of scratch x21, below x28: reg = its address. Uses x9, x10. */
.macro DA_LIST reg, stride
    MOVQ    x9, \stride
    mul     x9, x23, x9
    add     x9, x9, #LIST_FIXED
    sub     x28, x28, x9
    add     \reg, x21, x28
    mov     x10, #LIST_FIXED
    stp     x9, x10, [\reg]
    str     x23, [\reg, #LIST_COUNT]
.endm

/*
 * x19 sidecar, x20 settings, x21 scratch, x22 out, x23 n, x24 commitments, x25 cell indices,
 * x26 cells, x27 proofs, x28 scratch size left. Locals: L valid.
 */
SPEC_FUNCTION verify_data_column_sidecar_kzg_proofs
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    str     xzr, [x22]
    LDQ     x23, x19, DataColumnSidecar_kzg_commitments + 8
    MOVQ    x9, DA_SCRATCH_PER_BLOB
    umulh   x10, x23, x9
    cbnz    x10, 9f
    mul     x9, x23, x9
    MOVQ    x10, DA_SCRATCH_FIXED
    adds    x9, x9, x10
    b.cs    9f
    ldr     x28, [x21]
    cmp     x28, x9
    b.lo    9f
    DA_LIST x24, 48                         /* commitments_bytes = sidecar.kzg_commitments */
    DA_LIST x25, 8                          /* cell_indices = [sidecar.index] * len(sidecar.column) */
    DA_LIST x26, CRYPTO_KZG_CELL_SIZE       /* cells = sidecar.column */
    DA_LIST x27, 48                         /* proofs_bytes = sidecar.kzg_proofs */
    add     x0, x24, #LIST_FIXED
    PART    x1, x2, x19, DataColumnSidecar_kzg_commitments
    mov     x9, #48
    mul     x2, x2, x9
    bl      lantern_copy
    ldr     x9, [x19, #DataColumnSidecar_index]
    add     x10, x25, #LIST_FIXED
    mov     x11, x23
1:  cbz     x11, 2f
    str     x9, [x10], #8
    sub     x11, x11, #1
    b       1b
2:  add     x0, x26, #LIST_FIXED
    PART    x1, x2, x19, DataColumnSidecar_column
    lsl     x2, x2, #11
    bl      lantern_copy
    add     x0, x27, #LIST_FIXED
    PART    x1, x2, x19, DataColumnSidecar_kzg_proofs
    mov     x9, #48
    mul     x2, x2, x9
    bl      lantern_copy
    str     x28, [x21]                      /* asm-crypto's scratch: the front */
    mov     x0, x20
    mov     x1, x24
    mov     x2, x25
    mov     x3, x26
    mov     x4, x27
    mov     x5, x21
    add     x6, sp, #L
    CALL_GLOBAL crypto_kzg_verify_cell_kzg_proof_batch
    cmp     x0, #CRYPTO_BUFFER_TOO_SMALL
    b.eq    9f
    cbnz    x0, 8f                          /* an input that does not decode: the spec raises */
    ldr     x9, [sp, #L]
    str     x9, [x22]
8:  mov     x0, #LANTERN_OK
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END verify_data_column_sidecar_kzg_proofs

.if CRYPTO_KZG_CELL_SIZE != 2048
.error "lantern_verify_data_column_sidecar_kzg_proofs sizes cells with a shift by 11"
.endif

/* x19 sidecar, x20 settings, x21 config, x22 scratch, x23 out, x24 sidecars left, x25 scratch size. */
SPEC_FUNCTION is_data_available
    ENTER 16
    PART    x19, x24, x0, 8                 /* a standalone list: its PartRef at 8 */
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x25, [x22]
    mov     x9, #1                          /* all([]) is True */
    str     x9, [x23]
1:  cbz     x24, 8f
    mov     x0, x19                         /* verify_data_column_sidecar(column_sidecar) */
    mov     x1, x21
    mov     x2, x23
    bl      lantern_verify_data_column_sidecar
    ldr     x9, [x23]
    cbz     x9, 8f
    str     x25, [x22]                      /* and verify_data_column_sidecar_kzg_proofs(column_sidecar) */
    mov     x0, x19
    mov     x1, x20
    mov     x2, x22
    mov     x3, x23
    bl      lantern_verify_data_column_sidecar_kzg_proofs
    cbnz    x0, 7f
    ldr     x9, [x23]
    cbz     x9, 8f
    ldr     x9, [x19]
    add     x19, x19, x9
    sub     x24, x24, #1
    b       1b
8:  mov     x0, #LANTERN_OK
7:  LEAVE 16
SPEC_END is_data_available
.endif
