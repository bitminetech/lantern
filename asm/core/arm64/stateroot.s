/*
 * The hash tree root of a state from a StateCache, ARM64. Requirements: docs/reference/state.md.
 */

/* The area at the end of scratch that lantern_state_root keeps for itself. */
.set STATE_ROOT_ZEROS, 0                            /* the zero hash of each depth, 0 to 40 */
.set STATE_ROOT_LEAVES, 41 * 32                     /* the root of each field, then zeros to the width */
.set STATE_ROOT_HASH, STATE_ROOT_LEAVES + 64 * 32   /* a ByteList of the 64 bytes to hash */
.set STATE_ROOT_CHUNK, STATE_ROOT_HASH + 24 + 64    /* a last chunk, padded, or a length */
.set STATE_ROOT_AREA, 4096

/* SrCtx: the work of lantern_sr_tree on one tree, or of one job on a range of its leaves. */
.set SrCtx_tree, 0                                  /* the CacheTree */
.set SrCtx_data, 8
.set SrCtx_count, 16                                /* elements */
.set SrCtx_elem, 24                                 /* bytes of a basic element, or 0 */
.set SrCtx_desc, 32
.set SrCtx_depth, 40                                /* the limit's depth */
.set SrCtx_list, 48
.set SrCtx_out, 56
.set SrCtx_front, 64                                /* the scratch size its ssz calls get */
.set SrCtx_bytes, 72                                /* count * elem */
.set SrCtx_leaves, 80
.set SrCtx_cache, 88
.set SrCtx_scratch, 96
.set SrCtx_area, 104
.set SrCtx_status, 112                              /* a job's status */
.set SrCtx_lo, 120                                  /* the leaves of its range */
.set SrCtx_hi, 128
.set SrCtx_levels, 136                              /* the levels it hashes */
.set SrCtx_pool, 144                                /* a ShellPool, or 0 */
.set SrCtx_old, 152                                 /* the tree's count before */
.set SrCtx__mem, 160
.set SR_JOB_BYTES, 12288                            /* a job's region: its SrCtx, its area, its scratch */
.set SR_JOB_AREA, 256
.set SR_JOB_SCRATCH, SR_JOB_AREA + STATE_ROOT_AREA
.set SR_JOB_MIN, 4096                               /* a job's leaves at least: 64 words of dirty bits */
.set SR_JOBS_MAX, 64
.set SR_JOBS_SHIFT, 6

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
 * Lays out the trees of the StateCache table for x0 validators, into cache x1 when it is not
 * 0; x0 = the bytes of the cache. A leaf.
 */
LOCAL_FUNCTION lantern_sr_layout
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
END_FUNCTION lantern_sr_layout

/* Locals: sp+16 size. */
SPEC_FUNCTION state_cache_size
    FRAME 16
    str     x1, [sp, #16]
    ldr     x0, [x0]
    mov     x1, #0
    bl      lantern_sr_layout
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
    bl      lantern_sr_layout
    ldp     x1, x9, [sp, #16]
    ldr     x10, [x1, #StateCache_size]
    cmp     x10, x0
    b.lo    9f
    str     x9, [x1, #StateCache_validators]
    mov     x0, x9
    bl      lantern_sr_layout
    mov     x0, #LANTERN_OK
    UNFRAME 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    UNFRAME 16
SPEC_END state_cache_init

.if FORK > FORK_PHASE0
/* SHA-256 of the 32 bytes at x0 and the 32 bytes at x1, to x2, which may be x0 or x1. x23 the area. */
LOCAL_FUNCTION lantern_sr_hash
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
END_FUNCTION lantern_sr_hash

/* The zero hash of each depth 0 to 40 in the area at x23. x19 the next, x20 the hashes left. */
LOCAL_FUNCTION lantern_sr_zeros
    ENTER 16
    mov     x19, x23
    stp     xzr, xzr, [x19]
    stp     xzr, xzr, [x19, #16]
    mov     x20, #40
1:  mov     x0, x19
    mov     x1, x19
    add     x2, x19, #32
    bl      lantern_sr_hash
    add     x19, x19, #32
    subs    x20, x20, #1
    b.ne    1b
    LEAVE 16
END_FUNCTION lantern_sr_zeros

/*
 * The root of a field from tree x0 (a CacheTree): data x1, count x2 elements, x3 the bytes of
 * an element of a basic type or 0 for containers of descriptor x4, the limit's depth x5, x6 1 for
 * a list (mixed with the count), the root to x7, x8 a ShellPool or 0. x0 = 0, 1 when the leaves
 * pass the capacity, or a status of ssz_hash_tree_root. x20 the cache, x21 scratch with its
 * front's size set, x23 the area. With a pool and at least two jobs of leaves, jobs of
 * lantern_sr_job hash ranges of the leaves and their lower levels at once, each in a region of
 * SR_JOB_BYTES at the end of the front; a failed job makes the tree's work start again alone.
 * x19 the SrCtx, x24 the leaves, x25 the jobs' leaves, x26 the jobs, x27 the first region,
 * x28 a job. Locals: L the SrCtx, L+SrCtx__mem a ShellJob.
 */
LOCAL_FUNCTION lantern_sr_tree
    ENTER (SrCtx__mem + 32)
    add     x19, sp, #L
    stp     x0, x1, [x19, #SrCtx_tree]
    stp     x2, x3, [x19, #SrCtx_count]
    stp     x4, x5, [x19, #SrCtx_desc]
    stp     x6, x7, [x19, #SrCtx_list]
    str     x8, [x19, #SrCtx_pool]
    ldr     x9, [x21]
    str     x9, [x19, #SrCtx_front]
    mul     x9, x2, x3
    str     x9, [x19, #SrCtx_bytes]
    mov     x24, x2                         /* the leaves: elements, or chunks */
    cbz     x3, 1f
    add     x24, x9, #31
    lsr     x24, x24, #5
1:  str     x24, [x19, #SrCtx_leaves]
    stp     x20, x21, [x19, #SrCtx_cache]
    str     x23, [x19, #SrCtx_area]
    stp     xzr, xzr, [x19, #SrCtx_status]  /* the status, and lo 0 */
    str     x24, [x19, #SrCtx_hi]
    mov     x9, #64
    str     x9, [x19, #SrCtx_levels]
    ldr     x9, [x0, #CacheTree_capacity]
    cmp     x24, x9
    b.ls    2f
    mov     x0, #1
    LEAVE (SrCtx__mem + 32)
2:  ldr     x28, [x0, #CacheTree_count]
    str     x28, [x19, #SrCtx_old]
    cmp     x24, x28                        /* fewer leaves than the last root: the last one is dirty */
    b.hs    3f
    cbz     x24, 3f
    ldr     x9, [x0, #CacheTree_dirty]
    add     x27, x20, x9
    sub     x9, x24, #1
    lsr     x10, x9, #6
    ldr     x11, [x27, x10, lsl #3]
    mov     x12, #1
    lsl     x12, x12, x9
    orr     x11, x11, x12
    str     x11, [x27, x10, lsl #3]
3:  ldr     x9, [x19, #SrCtx_pool]          /* the jobs: 2 to SR_JOBS_MAX of a power of two of leaves */
    cbz     x9, 50f
    add     x10, x24, #(SR_JOBS_MAX - 1)
    lsr     x10, x10, #SR_JOBS_SHIFT
    mov     x25, #SR_JOB_MIN
    cmp     x10, x25
    b.ls    4f
    sub     x10, x10, #1
    clz     x11, x10
    mov     x12, #64
    sub     x11, x12, x11
    mov     x25, #1
    lsl     x25, x25, x11
4:  add     x26, x24, x25
    sub     x26, x26, #1
    udiv    x26, x26, x25
    cmp     x26, #2
    b.lo    50f
    MOVQ    x9, SR_JOB_BYTES                /* their regions at the end of the front */
    mul     x10, x26, x9
    ldr     x11, [x19, #SrCtx_front]
    cmp     x10, x11
    b.hi    50f
    sub     x27, x11, x10
    add     x27, x21, x27
    mov     x28, #0
5:  cmp     x28, x26
    b.hs    6f
    MOVQ    x9, SR_JOB_BYTES
    madd    x0, x28, x9, x27
    mov     x1, x19
    mov     x2, #SrCtx__mem
    bl      lantern_copy
    MOVQ    x9, SR_JOB_BYTES
    madd    x22, x28, x9, x27               /* its range of leaves and its levels */
    mul     x10, x28, x25
    add     x11, x10, x25
    cmp     x11, x24
    csel    x11, x11, x24, ls
    stp     x10, x11, [x22, #SrCtx_lo]
    clz     x12, x25
    mov     x13, #(63 - 6)
    sub     x12, x13, x12
    str     x12, [x22, #SrCtx_levels]
    add     x0, x22, #SR_JOB_AREA           /* its area: the zero hashes and a hash input */
    str     x0, [x22, #SrCtx_area]
    mov     x1, x23
    mov     x2, #(41 * 32)
    bl      lantern_copy
    add     x12, x22, #(SR_JOB_AREA + STATE_ROOT_HASH)
    mov     x9, #(24 + 64)
    mov     x10, #24
    stp     x9, x10, [x12]
    mov     x11, #64
    str     x11, [x12, #16]
    MOVQ    x9, (SR_JOB_BYTES - SR_JOB_SCRATCH)    /* its scratch */
    ADDQ    x10, x22, SR_JOB_SCRATCH
    str     x9, [x10]
    str     x10, [x22, #SrCtx_scratch]
    str     x9, [x22, #SrCtx_front]
    add     x28, x28, #1
    b       5b
6:  add     x1, sp, #(L + SrCtx__mem)       /* the run */
    ADDRESS x9, lantern_sr_job
    stp     x9, x27, [x1, #ShellJob_function]
    str     x26, [x1, #ShellJob_count]
    ldr     x0, [x19, #SrCtx_pool]
    CALL_GLOBAL lantern_shell_pool_run
    mov     x28, #0                         /* a failed job: the tree alone, from no leaves */
7:  cmp     x28, x26
    b.hs    8f
    MOVQ    x9, SR_JOB_BYTES
    madd    x22, x28, x9, x27
    ldr     x9, [x22, #SrCtx_status]
    cbnz    x9, 71f
    add     x28, x28, #1
    b       7b
71: mov     x0, x19
    bl      lantern_sr_clean
    ldr     x9, [x19, #SrCtx_front]         /* the front, as on entry */
    str     x9, [x21]
    b       50f
8:  mov     x0, x19                         /* then the upper levels */
    ldr     x1, [x27, #SrCtx_levels]
    bl      lantern_sr_levels
    ldr     x9, [x19, #SrCtx_front]
    str     x9, [x21]
    b       60f
50: mov     x0, x19                         /* alone: the leaves, then every level */
    bl      lantern_sr_leaves
    cbz     x0, 51f
    str     x0, [x19, #SrCtx_status]        /* a failure: the tree holds nothing */
    mov     x0, x19
    bl      lantern_sr_clean
    ldr     x0, [x19, #SrCtx_status]
    LEAVE (SrCtx__mem + 32)
51: mov     x0, x19
    mov     x1, #0
    bl      lantern_sr_levels
60: mov     x0, x19
    bl      lantern_sr_post
    mov     x0, #0
    LEAVE (SrCtx__mem + 32)
END_FUNCTION lantern_sr_tree

/* A job of lantern_sr_tree: the SrCtx of job x1 of the regions at x0, its leaves then its levels; its status in it. x19 the SrCtx. */
LOCAL_FUNCTION lantern_sr_job
    ENTER 0
    MOVQ    x9, SR_JOB_BYTES
    madd    x19, x1, x9, x0
    mov     x0, x19
    bl      lantern_sr_leaves
    str     x0, [x19, #SrCtx_status]
    cbnz    x0, 9f
    mov     x0, x19
    mov     x1, #0
    bl      lantern_sr_levels
9:  mov     x0, #0
    LEAVE 0
END_FUNCTION lantern_sr_job

/*
 * The leaves lo to hi of the SrCtx x0: a chunk, or an element's root, that differs from the last
 * root's is written and made dirty. x0 = 0, or a status of ssz_hash_tree_root. x19 the SrCtx,
 * x20 the cache, x21 scratch, x22 data, x23 the area, x24 hi, x25 a leaf, x26 the level's nodes,
 * x27 its dirty bits, x28 the old count. Locals: L the tree.
 */
LOCAL_FUNCTION lantern_sr_leaves
    ENTER 16
    mov     x19, x0
    ldr     x9, [x19, #SrCtx_tree]
    str     x9, [sp, #L]
    ldp     x20, x21, [x19, #SrCtx_cache]
    ldr     x23, [x19, #SrCtx_area]
    ldr     x22, [x19, #SrCtx_data]
    ldp     x25, x24, [x19, #SrCtx_lo]
    ldr     x28, [x19, #SrCtx_old]
    ldr     x10, [x9, #CacheTree_nodes]
    add     x26, x20, x10
    ldr     x10, [x9, #CacheTree_dirty]
    add     x27, x20, x10
3:  cmp     x25, x24
    b.hs    20f
    add     x10, x26, x25, lsl #5           /* the leaf */
    ldr     x9, [x19, #SrCtx_elem]
    cbz     x9, 10f
    add     x11, x22, x25, lsl #5           /* the chunk; the last one padded */
    add     x12, x25, #1
    ldr     x13, [x19, #SrCtx_leaves]
    cmp     x12, x13
    b.ne    5f
    ldr     x13, [x19, #SrCtx_bytes]
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
10: ldr     x16, [sp, #L]                   /* an element and its copy */
    ldr     x9, [x16, #CacheTree_copy]
    mul     x11, x25, x9
    add     x12, x22, x11
    ldr     x13, [x16, #CacheTree_copies]
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
    ldr     x9, [x19, #SrCtx_front]
    str     x9, [x21]
    ldr     x0, [x19, #SrCtx_desc]
    mov     x1, x12
    mov     x2, x21
    add     x3, x26, x25, lsl #5
    CALL_GLOBAL ssz_hash_tree_root
    cbz     x0, 18f
    LEAVE 16
18: lsr     x9, x25, #6                     /* the leaf is dirty */
    ldr     x10, [x27, x9, lsl #3]
    mov     x11, #1
    lsl     x11, x11, x25
    orr     x10, x10, x11
    str     x10, [x27, x9, lsl #3]
19: add     x25, x25, #1
    b       3b
20: mov     x0, #0
    LEAVE 16
END_FUNCTION lantern_sr_leaves

/* The level of the SrCtx at x19: x26 its nodes, x27 its dirty bits, x28 its capacity, x24 its nodes in use, x22 it, to the next. */
.macro SR_UP
    add     x26, x26, x28, lsl #5
    add     x9, x28, #63
    lsr     x9, x9, #6
    add     x27, x27, x9, lsl #3
    add     x28, x28, #1
    lsr     x28, x28, #1
    add     x24, x24, #1
    lsr     x24, x24, #1
    add     x22, x22, #1
.endm

/*
 * From level x1 of the SrCtx x0, level by level up to its `levels`, the parents of dirty nodes of
 * its range lo to hi. x19 the SrCtx, x20 the cache, x21 the last level, x22 the level, x23 the
 * area, x24 the level's nodes in use, x25 a word, x26 the level's nodes, x27 its dirty bits, x28
 * its capacity. Locals: L the next level's nodes, L+8 its dirty bits, L+16 a word, L+24 a
 * parent, L+32 lo, L+40 hi, L+48 the words' end.
 */
LOCAL_FUNCTION lantern_sr_levels
    ENTER 64
    mov     x19, x0
    ldr     x9, [x19, #SrCtx_tree]
    ldr     x20, [x19, #SrCtx_cache]
    ldr     x23, [x19, #SrCtx_area]
    ldr     x21, [x19, #SrCtx_levels]
    ldr     x10, [x9, #CacheTree_nodes]
    add     x26, x20, x10
    ldr     x10, [x9, #CacheTree_dirty]
    add     x27, x20, x10
    ldr     x28, [x9, #CacheTree_capacity]
    ldr     x24, [x19, #SrCtx_leaves]
    ldp     x10, x11, [x19, #SrCtx_lo]
    stp     x10, x11, [sp, #(L + 32)]
    mov     x22, #0
    mov     x25, x1
1:  cmp     x22, x25                        /* up to the first level */
    b.hs    22f
    SR_UP
    ldp     x10, x11, [sp, #(L + 32)]
    lsr     x10, x10, #1
    add     x11, x11, #1
    lsr     x11, x11, #1
    stp     x10, x11, [sp, #(L + 32)]
    b       1b
22: cmp     x24, #1
    b.ls    30f
    cmp     x22, x21
    b.hs    30f
    add     x9, x26, x28, lsl #5
    str     x9, [sp, #L]
    add     x10, x28, #63
    lsr     x10, x10, #6
    add     x10, x27, x10, lsl #3
    str     x10, [sp, #(L + 8)]
    ldp     x10, x11, [sp, #(L + 32)]       /* the words of the range */
    lsr     x25, x10, #6
    add     x11, x11, #63
    lsr     x11, x11, #6
    add     x12, x24, #63
    lsr     x12, x12, #6
    cmp     x11, x12
    csel    x11, x11, x12, lo
    str     x11, [sp, #(L + 48)]
23: ldr     x9, [sp, #(L + 48)]
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
    stp     x12, x13, [sp, #(L + 16)]
    add     x0, x26, x13, lsl #6            /* the left child */
    lsl     x9, x13, #1
    add     x9, x9, #1
    add     x1, x26, x9, lsl #5             /* the right child, or the zero hash past the level */
    cmp     x9, x24
    b.lo    26f
    add     x1, x23, x22, lsl #5
26: ldr     x2, [sp, #L]
    add     x2, x2, x13, lsl #5
    bl      lantern_sr_hash
    ldp     x12, x13, [sp, #(L + 16)]
    ldr     x10, [sp, #(L + 8)]             /* the parent is dirty */
    lsr     x9, x13, #6
    ldr     x11, [x10, x9, lsl #3]
    mov     x14, #1
    lsl     x14, x14, x13
    orr     x11, x11, x14
    str     x11, [x10, x9, lsl #3]
    b       24b
28: add     x25, x25, #1
    b       23b
29: SR_UP
    ldp     x10, x11, [sp, #(L + 32)]
    lsr     x10, x10, #1
    add     x11, x11, #1
    lsr     x11, x11, #1
    stp     x10, x11, [sp, #(L + 32)]
    b       22b
30: LEAVE 64
END_FUNCTION lantern_sr_levels

/*
 * The root of the SrCtx x0 from its top: up to the limit's depth with zero hashes, the length
 * mixed in for a list, to out; the tree's count becomes its leaves. x19 the SrCtx, x20 the cache,
 * x22 the level, x23 the area, x24 the nodes in use, x26 the level's nodes, x27 its dirty bits,
 * x28 its capacity.
 */
LOCAL_FUNCTION lantern_sr_post
    ENTER 0
    mov     x19, x0
    ldr     x9, [x19, #SrCtx_tree]
    ldr     x20, [x19, #SrCtx_cache]
    ldr     x23, [x19, #SrCtx_area]
    ldr     x10, [x9, #CacheTree_nodes]
    add     x26, x20, x10
    ldr     x10, [x9, #CacheTree_dirty]
    add     x27, x20, x10
    ldr     x28, [x9, #CacheTree_capacity]
    ldr     x24, [x19, #SrCtx_leaves]
    mov     x22, #0
1:  cmp     x24, #1                         /* the top */
    b.ls    2f
    SR_UP
    b       1b
2:  str     xzr, [x27]                      /* the top's bit */
    ldr     x7, [x19, #SrCtx_out]
    cbnz    x24, 31f
    ldr     x9, [x19, #SrCtx_depth]         /* no leaves: the zero hash of the limit's depth */
    add     x1, x23, x9, lsl #5
    COPY32  x7, x1
    b       33f
31: COPY32  x7, x26
32: ldr     x9, [x19, #SrCtx_depth]         /* up to the limit's depth */
    cmp     x22, x9
    b.hs    33f
    ldr     x0, [x19, #SrCtx_out]
    add     x1, x23, x22, lsl #5
    mov     x2, x0
    bl      lantern_sr_hash
    add     x22, x22, #1
    b       32b
33: ldr     x9, [x19, #SrCtx_list]          /* a list: mix_in_length */
    cbz     x9, 34f
    add     x1, x23, #STATE_ROOT_CHUNK
    ldr     x10, [x19, #SrCtx_count]
    stp     x10, xzr, [x1]
    stp     xzr, xzr, [x1, #16]
    ldr     x0, [x19, #SrCtx_out]
    mov     x2, x0
    bl      lantern_sr_hash
34: ldr     x9, [x19, #SrCtx_leaves]
    ldr     x10, [x19, #SrCtx_tree]
    str     x9, [x10, #CacheTree_count]
    LEAVE 0
END_FUNCTION lantern_sr_post

/* After a failure: the tree of the SrCtx x0 holds nothing, every dirty bit of each level 0. A leaf; uses x9-x13. */
LOCAL_FUNCTION lantern_sr_clean
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #SrCtx_tree]
    ldr     x10, [x0, #SrCtx_cache]
    str     xzr, [x9, #CacheTree_count]
    str     xzr, [x0, #SrCtx_old]
    ldr     x11, [x9, #CacheTree_dirty]
    add     x11, x10, x11
    ldr     x12, [x9, #CacheTree_capacity]
1:  add     x13, x12, #63
    lsr     x13, x13, #6
2:  cbz     x13, 3f
    str     xzr, [x11], #8
    sub     x13, x13, #1
    b       2b
3:  cmp     x12, #1
    b.ls    9f
    add     x12, x12, #1
    lsr     x12, x12, #1
    b       1b
9:  ret
END_FUNCTION lantern_sr_clean
.endif

/*
 * The root of each field of the state into the leaves of the area, in field order: x19 state, x20 cache, x21
 * scratch, x23 the area, x28 the size of the front; x24, x25 and x26 are its own. To 90f for a tree past its
 * capacity, 98f for a refusal of ssz.
 */
.macro SR_FIELD_ROOTS pool
    ADDRESS x24, state_root_fields
    mov     x25, #SR_COUNT
    add     x26, x23, #STATE_ROOT_LEAVES
1:  cbz     x25, 49f
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
.ifc \pool, none
    mov     x8, #0
.else
    ldr     x8, [sp, #(\pool)]
.endif
    bl      lantern_sr_tree
    cmp     x0, #1
    b.eq    90f
    cbnz    x0, 98f
40: add     x24, x24, #40
    add     x26, x26, #32
    sub     x25, x25, #1
    b       1b
49:
.endm

/*
 * x19 state, x20 cache, x21 scratch, x22 out, x23 the area at the end of scratch, x24 the field
 * record, x25 the fields left, x26 the field's root, x27 the scratch size on entry, x28 the size
 * of the front, which callees get.
 */
SPEC_LEAF state_root
    mov     x4, #0
    b       lantern_sr_root
SPEC_END state_root

/* (state, cache, scratch, out, pool): state.md. As lantern_state_root, with the jobs of lantern_sr_tree on pool. */
SPEC_LEAF state_root_pool
    b       lantern_sr_root
SPEC_END state_root_pool

/*
 * lantern_state_root with pool x4, or 0. x19 state, x20 cache, x21 scratch, x22 out, x23 the area at
 * the end of scratch, x24 the field record, x25 the fields left, x26 the field's root, x27 the scratch
 * size on entry, x28 the size of the front, which callees get. Locals: L the pool.
 */
LOCAL_FUNCTION lantern_sr_root
    ENTER 16
    str     x4, [sp, #L]
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
    bl      lantern_sr_zeros
    SR_FIELD_ROOTS L
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
    bl      lantern_sr_hash
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
END_FUNCTION lantern_sr_root

/*
 * x19 state, x20 cache, then a node, x21 scratch, x22 out, x23 the area at the end of scratch,
 * x24 the leaf's index, x25 the nodes of a level, x26 the next root of out, x27 the scratch size
 * on entry, x28 the size of the front, which callees get. Locals: L the field, L+8 the generalized
 * index.
 */
SPEC_FUNCTION state_branch
    ENTER 16
.if FORK == FORK_PHASE0
    mov     x0, #LANTERN_NO_STATE_ANSWER
    LEAVE 16
.else
    cmp     x1, #LC_BRANCH_FINALIZED_ROOT
    b.hi    97f
    mov     x19, x0
    str     x1, [sp, #L]
    mov     x20, x2
    mov     x21, x3
    mov     x22, x4
    ldr     x27, [x21]
    mov     x9, #(STATE_ROOT_WIDTH + 22)    /* the generalized index: current_sync_committee is field 22, next 23 */
    add     x9, x9, x1
    cmp     x1, #LC_BRANCH_FINALIZED_ROOT
    b.ne    1f
    mov     x9, #((STATE_ROOT_WIDTH + 20) * 2 + 1)  /* finalized_checkpoint (field 20), then its root */
1:  str     x9, [sp, #(L + 8)]
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
    bl      lantern_sr_zeros
    SR_FIELD_ROOTS none
    mov     x25, #SR_COUNT                  /* zeros to the width */
2:  cmp     x25, #STATE_ROOT_WIDTH
    b.hs    3f
    add     x9, x23, #STATE_ROOT_LEAVES
    add     x9, x9, x25, lsl #5
    stp     xzr, xzr, [x9]
    stp     xzr, xzr, [x9, #16]
    add     x25, x25, #1
    b       2b
3:  mov     x26, x22                        /* the branch; for the finalized root, the epoch's leaf first */
    ldr     x9, [sp, #L]
    add     x24, x9, #22
    cmp     x9, #LC_BRANCH_FINALIZED_ROOT
    b.ne    4f
    mov     x24, #20
    LDQ     x10, x19, BeaconState_finalized_checkpoint + Checkpoint_epoch
    stp     x10, xzr, [x26]
    stp     xzr, xzr, [x26, #16]
    add     x26, x26, #32
4:  mov     x25, #STATE_ROOT_WIDTH
5:  cmp     x25, #1                         /* each level: the sibling, then the level above */
    b.ls    7f
    eor     x9, x24, #1
    add     x10, x23, #STATE_ROOT_LEAVES
    add     x10, x10, x9, lsl #5
    COPY32  x26, x10
    add     x26, x26, #32
    lsr     x25, x25, #1
    mov     x20, #0
6:  add     x2, x23, #STATE_ROOT_LEAVES
    add     x0, x2, x20, lsl #6
    add     x1, x0, #32
    add     x2, x2, x20, lsl #5
    bl      lantern_sr_hash
    add     x20, x20, #1
    cmp     x20, x25
    b.lo    6b
    lsr     x24, x24, #1
    b       5b
7:  str     x27, [x21]
    mov     x0, #LANTERN_OK
    LEAVE 16
98: str     x27, [x21]
    LEAVE 16
99: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
97: mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 16
90: str     x27, [x21]                      /* ssz_build_proof of the state, into a Branch at the end of scratch */
    subs    x28, x27, #(24 + 8 * 32)
    b.lo    99b
    str     x28, [x21]
    add     x26, x21, x28
    mov     x9, #(24 + 8 * 32)
    mov     x10, #24
    stp     x9, x10, [x26]
    str     xzr, [x26, #16]
    ADDRESS x0, lantern_type_BeaconState
    mov     x1, x19
    add     x2, sp, #(L + 8)
    mov     x3, x21
    mov     x4, x26
    CALL_GLOBAL ssz_build_proof
    str     x27, [x21]
    cbnz    x0, 91f
    ldr     x2, [x26, #16]
    lsl     x2, x2, #5
    add     x1, x26, #24
    mov     x0, x22
    bl      lantern_copy
    mov     x0, #LANTERN_OK
91: LEAVE 16
.endif
SPEC_END state_branch
