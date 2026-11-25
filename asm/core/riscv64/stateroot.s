/*
 * The hash tree root of a state from a StateCache, RISC-V. Requirements: docs/reference/state.md.
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
 * Lays out the trees of the StateCache table for a0 validators, into cache a1 when it is not
 * 0; a0 = the bytes of the cache. A leaf. t0 the table, t1 the offset of the next tree's bytes,
 * t2 the tree, t3 its capacity, t4 its copy bytes, t5 its header.
 */
LOCAL_FUNCTION lantern_sr_layout
    UNWIND_END_PROLOGUE
    ADDRESS t0, state_cache_trees
    li      t1, STATE_CACHE_FIXED
    li      t2, 0
1:  ld      a4, 0(t0)                       # divisor, constant, copy bytes
    ld      t3, 8(t0)
    ld      t4, 16(t0)
    beqz    a4, 2f
    add     t3, a0, a4
    addi    t3, t3, -1
    divu    t3, t3, a4                      # capacity: ceil(validators / divisor)
2:  li      a5, CacheTree__mem
    mul     t5, t2, a5
    add     t5, t5, a1
    addi    t5, t5, StateCache_trees
    beqz    a1, 3f
    sd      t3, CacheTree_capacity(t5)
    sd      zero, CacheTree_count(t5)
    sd      t1, CacheTree_nodes(t5)
    sd      t4, CacheTree_copy(t5)
3:  mv      t6, t3                          # nodes and dirty words of each level
    li      a2, 0
    li      a3, 0
4:  add     a2, a2, t6
    addi    a4, t6, 63
    srli    a4, a4, 6
    add     a3, a3, a4
    li      a5, 1
    bleu    t6, a5, 5f
    addi    t6, t6, 1
    srli    t6, t6, 1
    j       4b
5:  slli    a2, a2, 5
    add     t1, t1, a2
    beqz    a1, 7f
    sd      t1, CacheTree_dirty(t5)
    add     a4, a1, t1                      # every dirty bit 0
    mv      a5, a3
6:  beqz    a5, 7f
    sd      zero, 0(a4)
    addi    a4, a4, 8
    addi    a5, a5, -1
    j       6b
7:  slli    a3, a3, 3
    add     t1, t1, a3
    li      a4, 0
    beqz    t4, 8f
    mv      a4, t1
    mul     a5, t3, t4
    add     t1, t1, a5
8:  beqz    a1, 9f
    sd      a4, CacheTree_copies(t5)
9:  addi    t0, t0, 24
    addi    t2, t2, 1
    li      a5, STATE_CACHE_TREES
    bltu    t2, a5, 1b
    mv      a0, t1
    ret
END_FUNCTION lantern_sr_layout

/* Locals: sp+0 size. */
SPEC_FUNCTION state_cache_size
    FRAME 16
    sd      a1, 0(sp)
    ld      a0, 0(a0)
    li      a1, 0
    call    lantern_sr_layout
    ld      a1, 0(sp)
    sd      a0, 0(a1)
    li      a0, LANTERN_OK
    UNFRAME 16
SPEC_END state_cache_size

/* Locals: sp+0 cache, sp+8 validators. */
SPEC_FUNCTION state_cache_init
    FRAME 16
    ld      a0, 0(a0)
    sd      a1, 0(sp)
    sd      a0, 8(sp)
    li      a1, 0
    call    lantern_sr_layout
    ld      a1, 0(sp)
    ld      t0, StateCache_size(a1)
    bltu    t0, a0, 9f
    ld      a0, 8(sp)
    sd      a0, StateCache_validators(a1)
    call    lantern_sr_layout
    li      a0, LANTERN_OK
    UNFRAME 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    UNFRAME 16
SPEC_END state_cache_init

.if FORK > FORK_PHASE0
/* SHA-256 of the 32 bytes at a0 and the 32 bytes at a1, to a2, which may be a0 or a1. s5 the area. */
LOCAL_FUNCTION lantern_sr_hash
    FRAME 16
    sd      a2, 0(sp)
    li      t0, STATE_ROOT_HASH + 24
    add     t0, s5, t0
    COPY32  t0, a0
    addi    t0, t0, 32
    COPY32  t0, a1
    li      a0, STATE_ROOT_HASH
    add     a0, s5, a0
    ld      a1, 0(sp)
    CALL_GLOBAL crypto_sha256
    UNFRAME 16
END_FUNCTION lantern_sr_hash

/* The zero hash of each depth 0 to 40 in the area at s5. s1 the next, s2 the hashes left. */
LOCAL_FUNCTION lantern_sr_zeros
    ENTER 16
    mv      s1, s5
    sd      zero, 0(s1)
    sd      zero, 8(s1)
    sd      zero, 16(s1)
    sd      zero, 24(s1)
    li      s2, 40
1:  mv      a0, s1
    mv      a1, s1
    addi    a2, s1, 32
    call    lantern_sr_hash
    addi    s1, s1, 32
    addi    s2, s2, -1
    bnez    s2, 1b
    LEAVE 16
END_FUNCTION lantern_sr_zeros

/*
 * The root of a field from tree a0 (a CacheTree): data a1, count a2 elements, a3 the bytes of
 * an element of a basic type or 0 for containers of descriptor a4, the limit's depth a5, a6 1 for
 * a list (mixed with the count), the root to a7. a0 = 0, 1 when the leaves pass the capacity, or a
 * status of ssz_hash_tree_root. s2 the cache, s3 scratch with its front's size set, s5 the area.
 * s1 tree, s4 data then the level, s6 the leaves then the nodes of the level, s7 a leaf then a
 * word, s8 the level's nodes, s9 its dirty bits, s10 the old count then the level's capacity.
 * Locals: L count, L+8 element bytes, L+16 descriptor, L+24 depth, L+32 list, L+40 out, L+48 the
 * front's size, L+56 data bytes, L+64 the next level's nodes, L+72 its dirty bits, L+80 a word,
 * L+88 a parent, L+96 the leaves, L+104 a status.
 */
LOCAL_FUNCTION lantern_sr_tree
    ENTER 112
    mv      s1, a0
    mv      s4, a1
    sd      a2, L(sp)
    sd      a3, (L + 8)(sp)
    sd      a4, (L + 16)(sp)
    sd      a5, (L + 24)(sp)
    sd      a6, (L + 32)(sp)
    sd      a7, (L + 40)(sp)
    ld      t0, 0(s3)
    sd      t0, (L + 48)(sp)
    mul     t0, a2, a3
    sd      t0, (L + 56)(sp)
    mv      s6, a2                          # the leaves: elements, or chunks
    beqz    a3, 1f
    addi    s6, t0, 31
    srli    s6, s6, 5
1:  sd      s6, (L + 96)(sp)
    ld      t0, CacheTree_capacity(s1)
    bleu    s6, t0, 2f
    li      a0, 1
    LEAVE 112
2:  ld      s10, CacheTree_count(s1)
    ld      t0, CacheTree_nodes(s1)
    add     s8, s2, t0
    ld      t0, CacheTree_dirty(s1)
    add     s9, s2, t0
    li      s7, 0
3:  bgeu    s7, s6, 20f
    slli    t1, s7, 5
    add     t1, s8, t1                      # the leaf
    ld      t0, (L + 8)(sp)
    beqz    t0, 10f
    slli    t2, s7, 5
    add     t2, s4, t2                      # the chunk; the last one padded
    addi    t3, s7, 1
    bne     t3, s6, 5f
    ld      t3, (L + 56)(sp)
    andi    t3, t3, 31
    beqz    t3, 5f
    li      t4, STATE_ROOT_CHUNK
    add     t4, s5, t4
    sd      zero, 0(t4)
    sd      zero, 8(t4)
    sd      zero, 16(t4)
    sd      zero, 24(t4)
    li      t5, 0
4:  add     t6, t2, t5
    lbu     t6, 0(t6)
    add     a2, t4, t5
    sb      t6, 0(a2)
    addi    t5, t5, 1
    bltu    t5, t3, 4b
    mv      t2, t4
5:  bgeu    s7, s10, 6f                     # a leaf of the last root stays when the chunk does
    ld      t3, 0(t2)
    ld      t4, 0(t1)
    bne     t3, t4, 6f
    ld      t3, 8(t2)
    ld      t4, 8(t1)
    bne     t3, t4, 6f
    ld      t3, 16(t2)
    ld      t4, 16(t1)
    bne     t3, t4, 6f
    ld      t3, 24(t2)
    ld      t4, 24(t1)
    bne     t3, t4, 6f
    j       19f
6:  COPY32  t1, t2
    j       18f
10: ld      t0, CacheTree_copy(s1)          # an element and its copy
    mul     t2, s7, t0
    add     t3, s4, t2
    ld      t4, CacheTree_copies(s1)
    add     t4, s2, t4
    add     t4, t4, t2
    bgeu    s7, s10, 12f
    li      t5, 0
11: add     t6, t3, t5
    ld      t6, 0(t6)
    add     a2, t4, t5
    ld      a2, 0(a2)
    bne     t6, a2, 12f
    addi    t5, t5, 8
    bltu    t5, t0, 11b
    j       19f
12: li      t5, 0                           # the copy takes the element, the leaf its root
13: add     t6, t3, t5
    ld      t6, 0(t6)
    add     a2, t4, t5
    sd      t6, 0(a2)
    addi    t5, t5, 8
    bltu    t5, t0, 13b
    ld      t0, (L + 48)(sp)
    sd      t0, 0(s3)
    ld      a0, (L + 16)(sp)
    mv      a1, t3
    mv      a2, s3
    mv      a3, t1
    CALL_GLOBAL ssz_hash_tree_root
    beqz    a0, 18f
    sd      a0, (L + 104)(sp)               # a failure: the tree holds nothing
    sd      zero, CacheTree_count(s1)
    addi    t0, s6, 63
    srli    t0, t0, 6
    mv      t1, s9
14: beqz    t0, 15f
    sd      zero, 0(t1)
    addi    t1, t1, 8
    addi    t0, t0, -1
    j       14b
15: ld      a0, (L + 104)(sp)
    LEAVE 112
18: srli    t0, s7, 6                       # the leaf is dirty
    slli    t0, t0, 3
    add     t0, s9, t0
    ld      t1, 0(t0)
    li      t2, 1
    sll     t2, t2, s7
    or      t1, t1, t2
    sd      t1, 0(t0)
19: addi    s7, s7, 1
    j       3b
20: bgeu    s6, s10, 21f                    # fewer leaves than the last root: the last one is dirty
    beqz    s6, 21f
    addi    t3, s6, -1
    srli    t0, t3, 6
    slli    t0, t0, 3
    add     t0, s9, t0
    ld      t1, 0(t0)
    li      t2, 1
    sll     t2, t2, t3
    or      t1, t1, t2
    sd      t1, 0(t0)
21: ld      s10, CacheTree_capacity(s1)
    li      s4, 0                           # level by level, the parents of dirty nodes
22: li      t0, 1
    bleu    s6, t0, 30f
    slli    t0, s10, 5
    add     t0, s8, t0
    sd      t0, (L + 64)(sp)
    addi    t1, s10, 63
    srli    t1, t1, 6
    slli    t1, t1, 3
    add     t1, s9, t1
    sd      t1, (L + 72)(sp)
    li      s7, 0
23: addi    t0, s6, 63
    srli    t0, t0, 6
    bgeu    s7, t0, 29f
    slli    t1, s7, 3
    add     t1, s9, t1
    ld      t2, 0(t1)
    beqz    t2, 28f
    sd      zero, 0(t1)
24: beqz    t2, 28f
    neg     t3, t2                          # the lowest dirty bit, alone, then its index
    and     t3, t2, t3
    xor     t2, t2, t3
    li      t4, 0
    srli    t5, t3, 32
    beqz    t5, 241f
    addi    t4, t4, 32
    mv      t3, t5
241: srli   t5, t3, 16
    beqz    t5, 242f
    addi    t4, t4, 16
    mv      t3, t5
242: srli   t5, t3, 8
    beqz    t5, 243f
    addi    t4, t4, 8
    mv      t3, t5
243: srli   t5, t3, 4
    beqz    t5, 244f
    addi    t4, t4, 4
    mv      t3, t5
244: srli   t5, t3, 2
    beqz    t5, 245f
    addi    t4, t4, 2
    mv      t3, t5
245: srli   t5, t3, 1
    beqz    t5, 246f
    addi    t4, t4, 1
246: andi   t5, t4, 1
    bnez    t5, 25f
    addi    t5, t4, 1                       # an even node covers its sibling
    li      t6, 1
    sll     t6, t6, t5
    not     t6, t6
    and     t2, t2, t6
25: slli    t5, s7, 6
    add     t4, t4, t5
    srli    t4, t4, 1                       # the parent
    sd      t2, (L + 80)(sp)
    sd      t4, (L + 88)(sp)
    slli    a0, t4, 6                       # the left child
    add     a0, s8, a0
    slli    t5, t4, 1
    addi    t5, t5, 1
    slli    a1, t5, 5                       # the right child, or the zero hash past the level
    add     a1, s8, a1
    bltu    t5, s6, 26f
    slli    a1, s4, 5
    add     a1, s5, a1
26: ld      a2, (L + 64)(sp)
    slli    t5, t4, 5
    add     a2, a2, t5
    call    lantern_sr_hash
    ld      t4, (L + 88)(sp)                # the parent is dirty
    ld      t0, (L + 72)(sp)
    srli    t1, t4, 6
    slli    t1, t1, 3
    add     t0, t0, t1
    ld      t1, 0(t0)
    li      t2, 1
    sll     t2, t2, t4
    or      t1, t1, t2
    sd      t1, 0(t0)
    ld      t2, (L + 80)(sp)
    j       24b
28: addi    s7, s7, 1
    j       23b
29: ld      s8, (L + 64)(sp)
    ld      s9, (L + 72)(sp)
    addi    s10, s10, 1
    srli    s10, s10, 1
    addi    s6, s6, 1
    srli    s6, s6, 1
    addi    s4, s4, 1
    j       22b
30: sd      zero, 0(s9)                     # the top's bit
    ld      t0, (L + 40)(sp)
    bnez    s6, 31f
    ld      t1, (L + 24)(sp)                # no leaves: the zero hash of the limit's depth
    slli    t1, t1, 5
    add     t1, s5, t1
    COPY32  t0, t1
    j       33f
31: COPY32  t0, s8
32: ld      t1, (L + 24)(sp)                # up to the limit's depth
    bgeu    s4, t1, 33f
    ld      a0, (L + 40)(sp)
    slli    a1, s4, 5
    add     a1, s5, a1
    mv      a2, a0
    call    lantern_sr_hash
    addi    s4, s4, 1
    j       32b
33: ld      t0, (L + 32)(sp)                # a list: mix_in_length
    beqz    t0, 34f
    li      a1, STATE_ROOT_CHUNK
    add     a1, s5, a1
    ld      t1, L(sp)
    sd      t1, 0(a1)
    sd      zero, 8(a1)
    sd      zero, 16(a1)
    sd      zero, 24(a1)
    ld      a0, (L + 40)(sp)
    mv      a2, a0
    call    lantern_sr_hash
34: ld      t0, (L + 96)(sp)
    sd      t0, CacheTree_count(s1)
    li      a0, 0
    LEAVE 112
END_FUNCTION lantern_sr_tree
.endif

# The root of each field of the state into the leaves of the area, in field order: s1 state, s2 cache, s3
# scratch, s5 the area, s10 the size of the front; s6, s7 and s8 are its own. To 90f for a tree past its
# capacity, 98f for a refusal of ssz.
.macro SR_FIELD_ROOTS
    ADDRESS s6, state_root_fields
    li      s7, SR_COUNT
    addi    s8, s5, STATE_ROOT_LEAVES
1:  beqz    s7, 49f
    sd      s10, 0(s3)
    ld      t0, 0(s6)                       # kind
    ld      t1, 8(s6)
    add     t1, s1, t1                      # the field
    li      t2, SR_LEAF
    bne     t0, t2, 3f
    sd      zero, 0(s8)
    sd      zero, 8(s8)
    sd      zero, 16(s8)
    sd      zero, 24(s8)
    ld      t2, 24(s6)
    li      t3, 0
2:  add     t4, t1, t3
    lbu     t4, 0(t4)
    add     t5, s8, t3
    sb      t4, 0(t5)
    addi    t3, t3, 1
    bltu    t3, t2, 2b
    j       40f
3:  li      t2, SR_TYPE
    beq     t0, t2, 4f
    li      t2, SR_NESTED
    bne     t0, t2, 5f
    ld      t2, 0(t1)                       # the nested value of the part
    add     t1, s1, t2
4:  ADDRESS a0, state_root_fields
    ld      t2, 24(s6)
    add     a0, a0, t2
    mv      a1, t1
    mv      a2, s3
    mv      a3, s8
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 98f
    j       40f
5:  li      t2, SR_PVEC
    bne     t0, t2, 6f
    mv      a1, t1                          # the bytes, as elements of 1 byte; no length
    ld      a2, 24(s6)
    li      a3, 1
    li      a4, 0
    li      a6, 0
    j       8f
6:  ld      t2, 0(t1)                       # a list: its part
    add     a1, s1, t2
    ld      a2, 8(t1)
    li      a6, 1
    li      t2, SR_PLIST
    bne     t0, t2, 7f
    ld      a3, 24(s6)
    li      a4, 0
    j       8f
7:  li      a3, 0                           # containers of a descriptor
    ADDRESS a4, state_root_fields
    ld      t2, 24(s6)
    add     a4, a4, t2
8:  ld      t2, 16(s6)                      # its tree
    li      t3, CacheTree__mem
    mul     t2, t2, t3
    add     a0, s2, t2
    addi    a0, a0, StateCache_trees
    ld      a5, 32(s6)
    mv      a7, s8
    call    lantern_sr_tree
    li      t0, 1
    beq     a0, t0, 90f
    bnez    a0, 98f
40: addi    s6, s6, 40
    addi    s8, s8, 32
    addi    s7, s7, -1
    j       1b
49:
.endm

/*
 * s1 state, s2 cache, s3 scratch, s4 out, s5 the area at the end of scratch, s6 the field record,
 * s7 the fields left, s8 the field's root, s10 the size of the front, which callees get.
 * Locals: L the scratch size on entry.
 */
SPEC_FUNCTION state_root
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    ld      t0, 0(s3)
    sd      t0, L(sp)
.if FORK > FORK_PHASE0
    beqz    s2, 90f
    li      t1, LANTERN_SCRATCH_FIXED
    bltu    t0, t1, 99f
    li      t1, STATE_ROOT_AREA
    sub     s10, t0, t1
    andi    s10, s10, -8
    add     s5, s3, s10
    li      t1, STATE_ROOT_HASH             # the hash input: a ByteList of 64 bytes
    add     t1, s5, t1
    li      t0, 24 + 64
    sd      t0, 0(t1)
    li      t0, 24
    sd      t0, 8(t1)
    li      t0, 64
    sd      t0, 16(t1)
    call    lantern_sr_zeros
    SR_FIELD_ROOTS
50: li      s7, SR_COUNT                    # zeros to the width, then merkleize
51: li      t0, STATE_ROOT_WIDTH
    bgeu    s7, t0, 52f
    slli    t1, s7, 5
    addi    t1, t1, STATE_ROOT_LEAVES
    add     t1, s5, t1
    sd      zero, 0(t1)
    sd      zero, 8(t1)
    sd      zero, 16(t1)
    sd      zero, 24(t1)
    addi    s7, s7, 1
    j       51b
52: li      s6, STATE_ROOT_WIDTH
53: li      t0, 1
    bleu    s6, t0, 55f
    srli    s6, s6, 1
    li      s7, 0
54: addi    t0, s5, STATE_ROOT_LEAVES
    slli    a0, s7, 6
    add     a0, t0, a0
    addi    a1, a0, 32
    slli    a2, s7, 5
    add     a2, t0, a2
    call    lantern_sr_hash
    addi    s7, s7, 1
    bltu    s7, s6, 54b
    j       53b
55: addi    t0, s5, STATE_ROOT_LEAVES
    COPY32  s4, t0
    ld      t0, L(sp)
    sd      t0, 0(s3)
    li      a0, LANTERN_OK
    LEAVE 16
98: ld      t0, L(sp)
    sd      t0, 0(s3)
    LEAVE 16
99: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
.endif
90: ld      t0, L(sp)                       # ssz_hash_tree_root of the state
    sd      t0, 0(s3)
    ADDRESS a0, lantern_type_BeaconState
    mv      a1, s1
    mv      a2, s3
    mv      a3, s4
    CALL_GLOBAL ssz_hash_tree_root
    LEAVE 16
SPEC_END state_root

/*
 * s1 state, s2 cache, then a node, s3 scratch, s4 out, s5 the area at the end of scratch, s6 the
 * leaf's index, s7 the nodes of a level, s9 the next root of out, s10 the size of the front, which
 * callees get. Locals: L the scratch size on entry, L+8 the field, L+16 the generalized index.
 */
SPEC_FUNCTION state_branch
    ENTER 32
.if FORK == FORK_PHASE0
    li      a0, LANTERN_NO_STATE_ANSWER
    LEAVE 32
.else
    li      t0, LC_BRANCH_FINALIZED_ROOT
    bgtu    a1, t0, 97f
    mv      s1, a0
    sd      a1, (L + 8)(sp)
    mv      s2, a2
    mv      s3, a3
    mv      s4, a4
    ld      t0, 0(s3)
    sd      t0, L(sp)
    addi    t1, a1, STATE_ROOT_WIDTH + 22   # the generalized index: current_sync_committee is field 22, next 23
    li      t2, LC_BRANCH_FINALIZED_ROOT
    bne     a1, t2, 1f
    li      t1, (STATE_ROOT_WIDTH + 20) * 2 + 1 # finalized_checkpoint (field 20), then its root
1:  sd      t1, (L + 16)(sp)
    beqz    s2, 90f
    li      t1, LANTERN_SCRATCH_FIXED
    bltu    t0, t1, 99f
    li      t1, STATE_ROOT_AREA
    sub     s10, t0, t1
    andi    s10, s10, -8
    add     s5, s3, s10
    li      t1, STATE_ROOT_HASH             # the hash input: a ByteList of 64 bytes
    add     t1, s5, t1
    li      t0, 24 + 64
    sd      t0, 0(t1)
    li      t0, 24
    sd      t0, 8(t1)
    li      t0, 64
    sd      t0, 16(t1)
    call    lantern_sr_zeros
    SR_FIELD_ROOTS
    li      s7, SR_COUNT                    # zeros to the width
2:  li      t0, STATE_ROOT_WIDTH
    bgeu    s7, t0, 3f
    slli    t1, s7, 5
    addi    t1, t1, STATE_ROOT_LEAVES
    add     t1, s5, t1
    sd      zero, 0(t1)
    sd      zero, 8(t1)
    sd      zero, 16(t1)
    sd      zero, 24(t1)
    addi    s7, s7, 1
    j       2b
3:  mv      s9, s4                          # the branch; for the finalized root, the epoch's leaf first
    ld      t0, (L + 8)(sp)
    addi    s6, t0, 22
    li      t1, LC_BRANCH_FINALIZED_ROOT
    bne     t0, t1, 4f
    li      s6, 20
    LDQ     t2, s1, BeaconState_finalized_checkpoint + Checkpoint_epoch
    sd      t2, 0(s9)
    sd      zero, 8(s9)
    sd      zero, 16(s9)
    sd      zero, 24(s9)
    addi    s9, s9, 32
4:  li      s7, STATE_ROOT_WIDTH
5:  li      t0, 1                           # each level: the sibling, then the level above
    bleu    s7, t0, 7f
    xori    t0, s6, 1
    slli    t0, t0, 5
    addi    t0, t0, STATE_ROOT_LEAVES
    add     t0, s5, t0
    COPY32  s9, t0
    addi    s9, s9, 32
    srli    s7, s7, 1
    li      s2, 0
6:  addi    t0, s5, STATE_ROOT_LEAVES
    slli    a0, s2, 6
    add     a0, t0, a0
    addi    a1, a0, 32
    slli    a2, s2, 5
    add     a2, t0, a2
    call    lantern_sr_hash
    addi    s2, s2, 1
    bltu    s2, s7, 6b
    srli    s6, s6, 1
    j       5b
7:  ld      t0, L(sp)
    sd      t0, 0(s3)
    li      a0, LANTERN_OK
    LEAVE 32
98: ld      t0, L(sp)
    sd      t0, 0(s3)
    LEAVE 32
99: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
97: li      a0, LANTERN_INVALID_EVENT
    LEAVE 32
90: ld      t0, L(sp)                       # ssz_build_proof of the state, into a Branch at the end of scratch
    sd      t0, 0(s3)
    li      t1, 24 + 8 * 32
    bltu    t0, t1, 99b
    sub     t0, t0, t1
    andi    t0, t0, -8
    sd      t0, 0(s3)
    add     s9, s3, t0
    sd      t1, 0(s9)
    li      t2, 24
    sd      t2, 8(s9)
    sd      zero, 16(s9)
    ADDRESS a0, lantern_type_BeaconState
    mv      a1, s1
    addi    a2, sp, L + 16
    mv      a3, s3
    mv      a4, s9
    CALL_GLOBAL ssz_build_proof
    ld      t0, L(sp)
    sd      t0, 0(s3)
    bnez    a0, 91f
    ld      a2, 16(s9)
    slli    a2, a2, 5
    addi    a1, s9, 24
    mv      a0, s4
    call    lantern_copy
    li      a0, LANTERN_OK
91: LEAVE 32
.endif
SPEC_END state_branch
