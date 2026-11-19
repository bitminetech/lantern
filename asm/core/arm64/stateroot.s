/*
 * The hash tree root of a state from a StateCache, ARM64. Requirements: docs/reference/state.md.
 */

/* The area at the end of scratch that lantern_state_root keeps for itself. */
.set STATE_ROOT_ZEROS, 0                            /* the zero hash of each depth, 0 to 40 */
.set STATE_ROOT_LEAVES, 41 * 32                     /* the root of each field, then zeros to the width */
.set STATE_ROOT_HASH, STATE_ROOT_LEAVES + 64 * 32   /* a ByteList of the 64 bytes to hash */
.set STATE_ROOT_CHUNK, STATE_ROOT_HASH + 24 + 64    /* a last chunk, padded, or a length */
.set STATE_ROOT_AREA, 4096

/* Field kinds of the table. */
.set SR_LEAF, 1                                     /* inline, its bytes padded: a = the bytes */
.set SR_TYPE, 2                                     /* inline, ssz_hash_tree_root: a = the descriptor */
.set SR_NESTED, 3                                   /* the nested value of its part: a = the descriptor */
.set SR_PVEC, 4                                     /* inline vector of basic values: a = the bytes */
.set SR_PLIST, 5                                    /* list of basic values: a = an element's bytes */
.set SR_CLIST, 6                                    /* list of containers: a = the element's descriptor */

SSZ_DEPTH SR_D_HROOT, SLOTS_PER_HISTORICAL_ROOT
SSZ_DEPTH SR_D_MIXES, EPOCHS_PER_HISTORICAL_VECTOR
SSZ_DEPTH SR_D_SLASH, EPOCHS_PER_SLASHINGS_VECTOR / 4
SSZ_DEPTH SR_D_HISTORICAL, HISTORICAL_ROOTS_LIMIT
SSZ_DEPTH SR_D_VOTES, EPOCHS_PER_ETH1_VOTING_PERIOD * SLOTS_PER_EPOCH
SSZ_DEPTH SR_D_VALIDATORS, VALIDATOR_REGISTRY_LIMIT
SSZ_DEPTH SR_D_BALANCES, VALIDATOR_REGISTRY_LIMIT / 4
SSZ_DEPTH SR_D_FLAGS, VALIDATOR_REGISTRY_LIMIT / 32
SSZ_DEPTH SR_D_DEPOSITS, PENDING_DEPOSITS_LIMIT
SSZ_DEPTH SR_D_WITHDRAWALS, PENDING_PARTIAL_WITHDRAWALS_LIMIT
SSZ_DEPTH SR_D_CONSOLIDATIONS, PENDING_CONSOLIDATIONS_LIMIT
SSZ_DEPTH SR_D_LOOKAHEAD, (MIN_SEED_LOOKAHEAD + 1) * SLOTS_PER_EPOCH / 4

    RODATA
    .p2align 3
/* Each tree of the StateCache table: the divisor of the validators (0: a constant), the constant, the copy bytes. */
state_cache_trees:
    .quad 1, 0, STATE_CACHE_COPY_Validator
    .quad 4, 0, 0
    .quad 4, 0, 0
    .quad 32, 0, 0
    .quad 32, 0, 0
    .quad 0, SLOTS_PER_HISTORICAL_ROOT, 0
    .quad 0, SLOTS_PER_HISTORICAL_ROOT, 0
    .quad 0, EPOCHS_PER_HISTORICAL_VECTOR, 0
    .quad 0, EPOCHS_PER_SLASHINGS_VECTOR / 4, 0
    .quad 0, STATE_CACHE_HISTORICAL_ROOTS, 0
    .quad 0, EPOCHS_PER_ETH1_VOTING_PERIOD * SLOTS_PER_EPOCH, STATE_CACHE_COPY_Eth1Data
    .quad 0, STATE_CACHE_LIST, STATE_CACHE_COPY_HistoricalSummary
    .quad 0, STATE_CACHE_PENDING_DEPOSITS, STATE_CACHE_COPY_PendingDeposit
    .quad 0, STATE_CACHE_LIST, STATE_CACHE_COPY_PendingPartialWithdrawal
    .quad 0, STATE_CACHE_LIST, STATE_CACHE_COPY_PendingConsolidation
    .quad 0, (MIN_SEED_LOOKAHEAD + 1) * SLOTS_PER_EPOCH / 4, 0

.if FORK > FORK_PHASE0
/* The fields of the fork's BeaconState, in order: kind, offset, tree, a, the limit's depth. */
.set SR_COUNT, 0
.macro SR_FIELD kind, field, tree, a, depth
    .quad \kind, BeaconState_\field, \tree, \a, \depth
    .set SR_COUNT, SR_COUNT + 1
.endm
.macro SR_TYPED kind, field, T
    .quad \kind, BeaconState_\field, 0, lantern_type_\T - state_root_fields, 0
    .set SR_COUNT, SR_COUNT + 1
.endm
.macro SR_LIST field, tree, T, depth
    .if \T\()__mem != STATE_CACHE_COPY_\T
    .error "SR_LIST: the tree's copy is not the element's __mem"
    .endif
    .quad SR_CLIST, BeaconState_\field, \tree, lantern_type_\T - state_root_fields, \depth
    .set SR_COUNT, SR_COUNT + 1
.endm

state_root_fields:
    SR_FIELD SR_LEAF, genesis_time, 0, 8, 0
    SR_FIELD SR_LEAF, genesis_validators_root, 0, 32, 0
    SR_FIELD SR_LEAF, slot, 0, 8, 0
    SR_TYPED SR_TYPE, fork, Fork
    SR_TYPED SR_TYPE, latest_block_header, BeaconBlockHeader
    SR_FIELD SR_PVEC, block_roots, 5, SLOTS_PER_HISTORICAL_ROOT * 32, SR_D_HROOT
    SR_FIELD SR_PVEC, state_roots, 6, SLOTS_PER_HISTORICAL_ROOT * 32, SR_D_HROOT
    SR_FIELD SR_PLIST, historical_roots, 9, 32, SR_D_HISTORICAL
    SR_TYPED SR_TYPE, eth1_data, Eth1Data
    SR_LIST eth1_data_votes, 10, Eth1Data, SR_D_VOTES
    SR_FIELD SR_LEAF, eth1_deposit_index, 0, 8, 0
    SR_LIST validators, 0, Validator, SR_D_VALIDATORS
    SR_FIELD SR_PLIST, balances, 1, 8, SR_D_BALANCES
    SR_FIELD SR_PVEC, randao_mixes, 7, EPOCHS_PER_HISTORICAL_VECTOR * 32, SR_D_MIXES
    SR_FIELD SR_PVEC, slashings, 8, EPOCHS_PER_SLASHINGS_VECTOR * 8, SR_D_SLASH
    SR_FIELD SR_PLIST, previous_epoch_participation, 3, 1, SR_D_FLAGS
    SR_FIELD SR_PLIST, current_epoch_participation, 4, 1, SR_D_FLAGS
    SR_FIELD SR_LEAF, justification_bits, 0, 1, 0
    SR_TYPED SR_TYPE, previous_justified_checkpoint, Checkpoint
    SR_TYPED SR_TYPE, current_justified_checkpoint, Checkpoint
    SR_TYPED SR_TYPE, finalized_checkpoint, Checkpoint
    SR_FIELD SR_PLIST, inactivity_scores, 2, 8, SR_D_BALANCES
    SR_TYPED SR_TYPE, current_sync_committee, SyncCommittee
    SR_TYPED SR_TYPE, next_sync_committee, SyncCommittee
.if FORK >= FORK_BELLATRIX
    SR_TYPED SR_NESTED, latest_execution_payload_header, ExecutionPayloadHeader
.endif
.if FORK >= FORK_CAPELLA
    SR_FIELD SR_LEAF, next_withdrawal_index, 0, 8, 0
    SR_FIELD SR_LEAF, next_withdrawal_validator_index, 0, 8, 0
    SR_LIST historical_summaries, 11, HistoricalSummary, SR_D_HISTORICAL
.endif
.if FORK >= FORK_ELECTRA
    SR_FIELD SR_LEAF, deposit_requests_start_index, 0, 8, 0
    SR_FIELD SR_LEAF, deposit_balance_to_consume, 0, 8, 0
    SR_FIELD SR_LEAF, exit_balance_to_consume, 0, 8, 0
    SR_FIELD SR_LEAF, earliest_exit_epoch, 0, 8, 0
    SR_FIELD SR_LEAF, consolidation_balance_to_consume, 0, 8, 0
    SR_FIELD SR_LEAF, earliest_consolidation_epoch, 0, 8, 0
    SR_LIST pending_deposits, 12, PendingDeposit, SR_D_DEPOSITS
    SR_LIST pending_partial_withdrawals, 13, PendingPartialWithdrawal, SR_D_WITHDRAWALS
    SR_LIST pending_consolidations, 14, PendingConsolidation, SR_D_CONSOLIDATIONS
.endif
.if FORK >= FORK_FULU
    SR_FIELD SR_PVEC, proposer_lookahead, 15, (MIN_SEED_LOOKAHEAD + 1) * SLOTS_PER_EPOCH * 8, SR_D_LOOKAHEAD
.endif
.if SR_COUNT > 32
.set STATE_ROOT_WIDTH, 64
.else
.set STATE_ROOT_WIDTH, 32
.endif
.endif

    .text

/*
 * L0: lays out the trees of the StateCache table for x0 validators, into cache x1 when it is not
 * 0; x0 = the bytes of the cache. A leaf.
 */
LOCAL_FUNCTION sr_layout
    UNWIND_END_PROLOGUE
    ADDRESS x2, state_cache_trees
    MOVQ    x3, STATE_CACHE_FIXED           /* the offset of the next tree's bytes */
    mov     x4, #0                          /* the tree */
1:  ldp     x5, x6, [x2]                    /* divisor, constant */
    ldr     x7, [x2, #16]                   /* copy bytes */
    cbz     x5, 2f
    add     x6, x0, x5
    sub     x6, x6, #1
    udiv    x6, x6, x5                      /* capacity: ceil(validators / divisor) */
2:  mov     x8, #CacheTree__mem
    madd    x8, x4, x8, x1
    add     x8, x8, #StateCache_trees
    cbz     x1, 3f
    str     x6, [x8, #CacheTree_capacity]
    str     xzr, [x8, #CacheTree_count]
    str     x3, [x8, #CacheTree_nodes]
    str     x7, [x8, #CacheTree_copy]
3:  mov     x9, x6                          /* nodes and dirty words of each level */
    mov     x10, #0
    mov     x11, #0
4:  add     x10, x10, x9
    add     x12, x9, #63
    lsr     x12, x12, #6
    add     x11, x11, x12
    cmp     x9, #1
    b.ls    5f
    add     x9, x9, #1
    lsr     x9, x9, #1
    b       4b
5:  add     x3, x3, x10, lsl #5
    cbz     x1, 7f
    str     x3, [x8, #CacheTree_dirty]
    add     x12, x1, x3                     /* every dirty bit 0 */
    mov     x13, x11
6:  cbz     x13, 7f
    str     xzr, [x12], #8
    sub     x13, x13, #1
    b       6b
7:  add     x3, x3, x11, lsl #3
    mov     x12, #0
    cbz     x7, 8f
    mov     x12, x3
    mul     x13, x6, x7
    add     x3, x3, x13
8:  cbz     x1, 9f
    str     x12, [x8, #CacheTree_copies]
9:  add     x2, x2, #24
    add     x4, x4, #1
    cmp     x4, #STATE_CACHE_TREES
    b.lo    1b
    mov     x0, x3
    ret
END_FUNCTION sr_layout

/* Locals: sp+16 size. */
SPEC_FUNCTION state_cache_size
    FRAME 16
    str     x1, [sp, #16]
    ldr     x0, [x0]
    mov     x1, #0
    bl      sr_layout
    ldr     x1, [sp, #16]
    str     x0, [x1]
    mov     x0, #LANTERN_OK
    UNFRAME 16
SPEC_END state_cache_size

/* Locals: sp+16 cache, sp+24 validators. */
SPEC_FUNCTION state_cache_init
    FRAME 16
    ldr     x0, [x0]
    stp     x1, x0, [sp, #16]
    mov     x1, #0
    bl      sr_layout
    ldp     x1, x9, [sp, #16]
    ldr     x10, [x1, #StateCache_size]
    cmp     x10, x0
    b.lo    9f
    str     x9, [x1, #StateCache_validators]
    mov     x0, x9
    bl      sr_layout
    mov     x0, #LANTERN_OK
    UNFRAME 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    UNFRAME 16
SPEC_END state_cache_init

.if FORK > FORK_PHASE0
/* L0: SHA-256 of the 32 bytes at x0 and the 32 bytes at x1, to x2, which may be x0 or x1. x23 the area. */
LOCAL_FUNCTION sr_hash
    FRAME 16
    str     x2, [sp, #16]
    add     x9, x23, #(STATE_ROOT_HASH + 24)
    COPY32  x9, x0
    add     x9, x9, #32
    COPY32  x9, x1
    add     x0, x23, #STATE_ROOT_HASH
    ldr     x1, [sp, #16]
    CALL_GLOBAL crypto_sha256
    UNFRAME 16
END_FUNCTION sr_hash

/* L0: the zero hash of each depth 0 to 40 in the area at x23. x19 the next, x20 the hashes left. */
LOCAL_FUNCTION sr_zeros
    ENTER 16
    mov     x19, x23
    stp     xzr, xzr, [x19]
    stp     xzr, xzr, [x19, #16]
    mov     x20, #40
1:  mov     x0, x19
    mov     x1, x19
    add     x2, x19, #32
    bl      sr_hash
    add     x19, x19, #32
    subs    x20, x20, #1
    b.ne    1b
    LEAVE 16
END_FUNCTION sr_zeros

/*
 * L0: the root of a field from tree x0 (a CacheTree): data x1, count x2 elements, x3 the bytes of
 * an element of a basic type or 0 for containers of descriptor x4, the limit's depth x5, x6 1 for
 * a list (mixed with the count), the root to x7. x0 = 0, 1 when the leaves pass the capacity, or a
 * status of ssz_hash_tree_root. x20 the cache, x21 scratch with its front's size set, x23 the area.
 * x19 tree, x22 data then the level, x24 the leaves then the nodes of the level, x25 a leaf then a
 * word, x26 the level's nodes, x27 the level's dirty bits, x28 the old count then the level's
 * capacity. Locals: L count, L+8 element bytes, L+16 descriptor, L+24 depth, L+32 list, L+40 out,
 * L+48 the front's size, L+56 data bytes, L+64 the next level's nodes, L+72 its dirty bits,
 * L+80 a word, L+88 a parent, L+96 the leaves, L+104 a status.
 */
LOCAL_FUNCTION sr_tree
    ENTER 112
    mov     x19, x0
    mov     x22, x1
    stp     x2, x3, [sp, #L]
    stp     x4, x5, [sp, #(L + 16)]
    stp     x6, x7, [sp, #(L + 32)]
    ldr     x9, [x21]
    str     x9, [sp, #(L + 48)]
    mul     x9, x2, x3
    str     x9, [sp, #(L + 56)]
    mov     x24, x2                         /* the leaves: elements, or chunks */
    cbz     x3, 1f
    add     x24, x9, #31
    lsr     x24, x24, #5
1:  str     x24, [sp, #(L + 96)]
    ldr     x9, [x19, #CacheTree_capacity]
    cmp     x24, x9
    b.ls    2f
    mov     x0, #1
    LEAVE 112
2:  ldr     x28, [x19, #CacheTree_count]
    ldr     x9, [x19, #CacheTree_nodes]
    add     x26, x20, x9
    ldr     x9, [x19, #CacheTree_dirty]
    add     x27, x20, x9
    mov     x25, #0
3:  cmp     x25, x24
    b.hs    20f
    add     x10, x26, x25, lsl #5           /* the leaf */
    ldr     x9, [sp, #(L + 8)]
    cbz     x9, 10f
    add     x11, x22, x25, lsl #5           /* the chunk; the last one padded */
    add     x12, x25, #1
    cmp     x12, x24
    b.ne    5f
    ldr     x13, [sp, #(L + 56)]
    ands    x13, x13, #31
    b.eq    5f
    add     x14, x23, #STATE_ROOT_CHUNK
    stp     xzr, xzr, [x14]
    stp     xzr, xzr, [x14, #16]
    mov     x15, #0
4:  ldrb    w16, [x11, x15]
    strb    w16, [x14, x15]
    add     x15, x15, #1
    cmp     x15, x13
    b.lo    4b
    mov     x11, x14
5:  cmp     x25, x28                        /* a leaf of the last root stays when the chunk does */
    b.hs    6f
    ldp     x12, x13, [x11]
    ldp     x14, x15, [x10]
    cmp     x12, x14
    ccmp    x13, x15, #0, eq
    b.ne    6f
    ldp     x12, x13, [x11, #16]
    ldp     x14, x15, [x10, #16]
    cmp     x12, x14
    ccmp    x13, x15, #0, eq
    b.eq    19f
6:  COPY32  x10, x11
    b       18f
10: ldr     x9, [x19, #CacheTree_copy]      /* an element and its copy */
    mul     x11, x25, x9
    add     x12, x22, x11
    ldr     x13, [x19, #CacheTree_copies]
    add     x13, x20, x13
    add     x13, x13, x11
    cmp     x25, x28
    b.hs    12f
    mov     x14, #0
11: ldr     x15, [x12, x14]
    ldr     x16, [x13, x14]
    cmp     x15, x16
    b.ne    12f
    add     x14, x14, #8
    cmp     x14, x9
    b.lo    11b
    b       19f
12: mov     x14, #0                         /* the copy takes the element, the leaf its root */
13: ldr     x15, [x12, x14]
    str     x15, [x13, x14]
    add     x14, x14, #8
    cmp     x14, x9
    b.lo    13b
    ldr     x9, [sp, #(L + 48)]
    str     x9, [x21]
    ldr     x0, [sp, #(L + 16)]
    mov     x1, x12
    mov     x2, x21
    add     x3, x26, x25, lsl #5
    CALL_GLOBAL ssz_hash_tree_root
    cbz     x0, 18f
    str     x0, [sp, #(L + 104)]            /* a failure: the tree holds nothing */
    str     xzr, [x19, #CacheTree_count]
    add     x9, x24, #63
    lsr     x9, x9, #6
14: cbz     x9, 15f
    sub     x9, x9, #1
    str     xzr, [x27, x9, lsl #3]
    b       14b
15: ldr     x0, [sp, #(L + 104)]
    LEAVE 112
18: lsr     x9, x25, #6                     /* the leaf is dirty */
    ldr     x10, [x27, x9, lsl #3]
    mov     x11, #1
    lsl     x11, x11, x25
    orr     x10, x10, x11
    str     x10, [x27, x9, lsl #3]
19: add     x25, x25, #1
    b       3b
20: cmp     x24, x28                        /* fewer leaves than the last root: the last one is dirty */
    b.hs    21f
    cbz     x24, 21f
    sub     x9, x24, #1
    lsr     x10, x9, #6
    ldr     x11, [x27, x10, lsl #3]
    mov     x12, #1
    lsl     x12, x12, x9
    orr     x11, x11, x12
    str     x11, [x27, x10, lsl #3]
21: ldr     x28, [x19, #CacheTree_capacity]
    mov     x22, #0                         /* level by level, the parents of dirty nodes */
22: cmp     x24, #1
    b.ls    30f
    add     x9, x26, x28, lsl #5
    str     x9, [sp, #(L + 64)]
    add     x10, x28, #63
    lsr     x10, x10, #6
    add     x10, x27, x10, lsl #3
    str     x10, [sp, #(L + 72)]
    mov     x25, #0
23: add     x9, x24, #63
    lsr     x9, x9, #6
    cmp     x25, x9
    b.hs    29f
    ldr     x12, [x27, x25, lsl #3]
    cbz     x12, 28f
    str     xzr, [x27, x25, lsl #3]
24: cbz     x12, 28f
    rbit    x13, x12
    clz     x13, x13                        /* the lowest dirty bit */
    mov     x14, #1
    lsl     x14, x14, x13
    bic     x12, x12, x14
    tst     x13, #1
    b.ne    25f
    lsl     x14, x14, #1                    /* an even node covers its sibling */
    bic     x12, x12, x14
25: add     x13, x13, x25, lsl #6
    lsr     x13, x13, #1                    /* the parent */
    stp     x12, x13, [sp, #(L + 80)]
    add     x0, x26, x13, lsl #6            /* the left child */
    lsl     x9, x13, #1
    add     x9, x9, #1
    add     x1, x26, x9, lsl #5             /* the right child, or the zero hash past the level */
    cmp     x9, x24
    b.lo    26f
    add     x1, x23, x22, lsl #5
26: ldr     x2, [sp, #(L + 64)]
    add     x2, x2, x13, lsl #5
    bl      sr_hash
    ldp     x12, x13, [sp, #(L + 80)]
    ldr     x10, [sp, #(L + 72)]            /* the parent is dirty */
    lsr     x9, x13, #6
    ldr     x11, [x10, x9, lsl #3]
    mov     x14, #1
    lsl     x14, x14, x13
    orr     x11, x11, x14
    str     x11, [x10, x9, lsl #3]
    b       24b
28: add     x25, x25, #1
    b       23b
29: ldr     x26, [sp, #(L + 64)]
    ldr     x27, [sp, #(L + 72)]
    add     x28, x28, #1
    lsr     x28, x28, #1
    add     x24, x24, #1
    lsr     x24, x24, #1
    add     x22, x22, #1
    b       22b
30: str     xzr, [x27]                      /* the top's bit */
    ldr     x7, [sp, #(L + 40)]
    cbnz    x24, 31f
    ldr     x9, [sp, #(L + 24)]             /* no leaves: the zero hash of the limit's depth */
    add     x1, x23, x9, lsl #5
    COPY32  x7, x1
    b       33f
31: COPY32  x7, x26
32: ldr     x9, [sp, #(L + 24)]             /* up to the limit's depth */
    cmp     x22, x9
    b.hs    33f
    ldr     x0, [sp, #(L + 40)]
    add     x1, x23, x22, lsl #5
    mov     x2, x0
    bl      sr_hash
    add     x22, x22, #1
    b       32b
33: ldr     x9, [sp, #(L + 32)]             /* a list: mix_in_length */
    cbz     x9, 34f
    add     x1, x23, #STATE_ROOT_CHUNK
    ldr     x10, [sp, #L]
    stp     x10, xzr, [x1]
    stp     xzr, xzr, [x1, #16]
    ldr     x0, [sp, #(L + 40)]
    mov     x2, x0
    bl      sr_hash
34: ldr     x9, [sp, #(L + 96)]
    str     x9, [x19, #CacheTree_count]
    mov     x0, #0
    LEAVE 112
END_FUNCTION sr_tree
.endif

/*
 * x19 state, x20 cache, x21 scratch, x22 out, x23 the area at the end of scratch, x24 the field
 * record, x25 the fields left, x26 the field's root, x27 the scratch size on entry, x28 the size
 * of the front, which callees get.
 */
SPEC_FUNCTION state_root
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    ldr     x27, [x21]
.if FORK > FORK_PHASE0
    cbz     x20, 90f
    MOVQ    x9, LANTERN_SCRATCH_FIXED
    cmp     x27, x9
    b.lo    99f
    sub     x28, x27, #STATE_ROOT_AREA
    add     x23, x21, x28
    mov     x9, #(24 + 64)                  /* the hash input: a ByteList of 64 bytes */
    mov     x10, #24
    mov     x11, #64
    add     x12, x23, #STATE_ROOT_HASH
    stp     x9, x10, [x12]
    str     x11, [x12, #16]
    bl      sr_zeros
    ADDRESS x24, state_root_fields
    mov     x25, #SR_COUNT
    add     x26, x23, #STATE_ROOT_LEAVES
1:  cbz     x25, 50f
    str     x28, [x21]
    ldr     x9, [x24]                       /* kind */
    ldr     x10, [x24, #8]
    add     x10, x19, x10                   /* the field */
    cmp     x9, #SR_LEAF
    b.ne    3f
    stp     xzr, xzr, [x26]
    stp     xzr, xzr, [x26, #16]
    ldr     x11, [x24, #24]
    mov     x12, #0
2:  ldrb    w13, [x10, x12]
    strb    w13, [x26, x12]
    add     x12, x12, #1
    cmp     x12, x11
    b.lo    2b
    b       40f
3:  cmp     x9, #SR_TYPE
    b.eq    4f
    cmp     x9, #SR_NESTED
    b.ne    5f
    ldr     x11, [x10]                      /* the nested value of the part */
    add     x10, x19, x11
4:  ADDRESS x0, state_root_fields
    ldr     x11, [x24, #24]
    add     x0, x0, x11
    mov     x1, x10
    mov     x2, x21
    mov     x3, x26
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 98f
    b       40f
5:  cmp     x9, #SR_PVEC
    b.ne    6f
    mov     x1, x10                         /* the bytes, as elements of 1 byte; no length */
    ldr     x2, [x24, #24]
    mov     x3, #1
    mov     x4, #0
    mov     x6, #0
    b       8f
6:  ldr     x11, [x10]                      /* a list: its part */
    add     x1, x19, x11
    ldr     x2, [x10, #8]
    mov     x6, #1
    cmp     x9, #SR_PLIST
    b.ne    7f
    ldr     x3, [x24, #24]
    mov     x4, #0
    b       8f
7:  mov     x3, #0                          /* containers of a descriptor */
    ADDRESS x4, state_root_fields
    ldr     x11, [x24, #24]
    add     x4, x4, x11
8:  ldr     x9, [x24, #16]                  /* its tree */
    mov     x10, #CacheTree__mem
    madd    x0, x9, x10, x20
    add     x0, x0, #StateCache_trees
    ldr     x5, [x24, #32]
    mov     x7, x26
    bl      sr_tree
    cmp     x0, #1
    b.eq    90f
    cbnz    x0, 98f
40: add     x24, x24, #40
    add     x26, x26, #32
    sub     x25, x25, #1
    b       1b
50: mov     x25, #SR_COUNT                  /* zeros to the width, then merkleize */
51: cmp     x25, #STATE_ROOT_WIDTH
    b.hs    52f
    add     x9, x23, #STATE_ROOT_LEAVES
    add     x9, x9, x25, lsl #5
    stp     xzr, xzr, [x9]
    stp     xzr, xzr, [x9, #16]
    add     x25, x25, #1
    b       51b
52: mov     x25, #STATE_ROOT_WIDTH
53: cmp     x25, #1
    b.ls    55f
    lsr     x25, x25, #1
    mov     x24, #0
54: add     x2, x23, #STATE_ROOT_LEAVES
    add     x0, x2, x24, lsl #6
    add     x1, x0, #32
    add     x2, x2, x24, lsl #5
    bl      sr_hash
    add     x24, x24, #1
    cmp     x24, x25
    b.lo    54b
    b       53b
55: add     x9, x23, #STATE_ROOT_LEAVES
    COPY32  x22, x9
    str     x27, [x21]
    mov     x0, #LANTERN_OK
    LEAVE 16
98: str     x27, [x21]
    LEAVE 16
99: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
.endif
90: str     x27, [x21]                      /* ssz_hash_tree_root of the state */
    ADDRESS x0, lantern_type_BeaconState
    mov     x1, x19
    mov     x2, x21
    mov     x3, x22
    CALL_GLOBAL ssz_hash_tree_root
    LEAVE 16
SPEC_END state_root
