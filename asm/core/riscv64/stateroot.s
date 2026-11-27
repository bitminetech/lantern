/*
 * The hash tree root of a state from a StateCache, RISC-V. Requirements: docs/reference/state.md.
 */

/* The area at the end of scratch that lantern_state_root keeps for itself. */
.set STATE_ROOT_ZEROS, 0                            /* the zero hash of each depth, 0 to 40 */
.set STATE_ROOT_LEAVES, 41 * 32                     /* the root of each field, then zeros to the width */
.set STATE_ROOT_HASH, STATE_ROOT_LEAVES + 64 * 32   /* a ByteList of the 64 bytes to hash */
.set STATE_ROOT_CHUNK, STATE_ROOT_HASH + 24 + 64    /* a last chunk, padded, or a length */
.set STATE_ROOT_AREA, 4096

# SrCtx: the work of lantern_sr_tree on one tree, or of one job on a range of its leaves.
.set SrCtx_tree, 0                                  # the CacheTree
.set SrCtx_data, 8
.set SrCtx_count, 16                                # elements
.set SrCtx_elem, 24                                 # bytes of a basic element, or 0
.set SrCtx_desc, 32
.set SrCtx_depth, 40                                # the limit's depth
.set SrCtx_list, 48
.set SrCtx_out, 56
.set SrCtx_front, 64                                # the scratch size its ssz calls get
.set SrCtx_bytes, 72                                # count * elem
.set SrCtx_leaves, 80
.set SrCtx_cache, 88
.set SrCtx_scratch, 96
.set SrCtx_area, 104
.set SrCtx_status, 112                              # a job's status
.set SrCtx_lo, 120                                  # the leaves of its range
.set SrCtx_hi, 128
.set SrCtx_levels, 136                              # the levels it hashes
.set SrCtx_pool, 144                                # a ShellPool, or 0
.set SrCtx_old, 152                                 # the tree's count before
.set SrCtx__mem, 160
.set SR_JOB_BYTES, 12288                            # a job's region: its SrCtx, its area, its scratch
.set SR_JOB_AREA, 256
.set SR_JOB_SCRATCH, SR_JOB_AREA + STATE_ROOT_AREA
.set SR_JOB_MIN, 4096                               # a job's leaves at least: 64 words of dirty bits
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
 * a list (mixed with the count), the root to a7, t6 a ShellPool or 0. a0 = 0, 1 when the leaves
 * pass the capacity, or a status of ssz_hash_tree_root. s2 the cache, s3 scratch with its front's
 * size set, s5 the area. With a pool and at least two jobs of leaves, jobs of lantern_sr_job hash
 * ranges of the leaves and their lower levels at once, each in a region of SR_JOB_BYTES at the end
 * of the front; a failed job makes the tree's work start again alone. s1 the SrCtx, s4 a job's
 * SrCtx, s6 the leaves, s7 the jobs' leaves, s8 the jobs, s9 the first region, s10 a job.
 * Locals: L the SrCtx, L+SrCtx__mem a ShellJob.
 */
LOCAL_FUNCTION lantern_sr_tree
    ENTER (SrCtx__mem + 32)
    addi    s1, sp, L
    sd      a0, SrCtx_tree(s1)
    sd      a1, SrCtx_data(s1)
    sd      a2, SrCtx_count(s1)
    sd      a3, SrCtx_elem(s1)
    sd      a4, SrCtx_desc(s1)
    sd      a5, SrCtx_depth(s1)
    sd      a6, SrCtx_list(s1)
    sd      a7, SrCtx_out(s1)
    sd      t6, SrCtx_pool(s1)
    ld      t0, 0(s3)
    sd      t0, SrCtx_front(s1)
    mul     t0, a2, a3
    sd      t0, SrCtx_bytes(s1)
    mv      s6, a2                          # the leaves: elements, or chunks
    beqz    a3, 1f
    addi    s6, t0, 31
    srli    s6, s6, 5
1:  sd      s6, SrCtx_leaves(s1)
    sd      s2, SrCtx_cache(s1)
    sd      s3, SrCtx_scratch(s1)
    sd      s5, SrCtx_area(s1)
    sd      zero, SrCtx_status(s1)
    sd      zero, SrCtx_lo(s1)
    sd      s6, SrCtx_hi(s1)
    li      t0, 64
    sd      t0, SrCtx_levels(s1)
    ld      t0, CacheTree_capacity(a0)
    bleu    s6, t0, 2f
    li      a0, 1
    LEAVE (SrCtx__mem + 32)
2:  ld      s10, CacheTree_count(a0)
    sd      s10, SrCtx_old(s1)
    bgeu    s6, s10, 3f                     # fewer leaves than the last root: the last one is dirty
    beqz    s6, 3f
    ld      t0, CacheTree_dirty(a0)
    add     s9, s2, t0
    addi    t1, s6, -1
    srli    t2, t1, 6
    slli    t2, t2, 3
    add     t2, s9, t2
    ld      t3, 0(t2)
    li      t4, 1
    sll     t4, t4, t1
    or      t3, t3, t4
    sd      t3, 0(t2)
3:  ld      t0, SrCtx_pool(s1)              # the jobs: 2 to SR_JOBS_MAX of a power of two of leaves
    beqz    t0, 50f
    addi    t1, s6, SR_JOBS_MAX - 1
    srli    t1, t1, SR_JOBS_SHIFT
    li      s7, SR_JOB_MIN
    bleu    t1, s7, 4f
    addi    t1, t1, -1                      # the bits of the count less 1
    li      t2, 0
41: srli    t1, t1, 1
    addi    t2, t2, 1
    bnez    t1, 41b
    li      s7, 1
    sll     s7, s7, t2
4:  add     s8, s6, s7
    addi    s8, s8, -1
    divu    s8, s8, s7
    li      t0, 2
    bltu    s8, t0, 50f
    li      t0, SR_JOB_BYTES                # their regions at the end of the front
    mul     t1, s8, t0
    ld      t2, SrCtx_front(s1)
    bltu    t2, t1, 50f
    sub     s9, t2, t1
    add     s9, s3, s9
    li      s10, 0
5:  bgeu    s10, s8, 6f
    li      t0, SR_JOB_BYTES
    mul     s4, s10, t0
    add     s4, s4, s9
    mv      a0, s4
    mv      a1, s1
    li      a2, SrCtx__mem
    call    lantern_copy
    mul     t0, s10, s7                     # its range of leaves and its levels
    sd      t0, SrCtx_lo(s4)
    add     t1, t0, s7
    bleu    t1, s6, 52f
    mv      t1, s6
52: sd      t1, SrCtx_hi(s4)
    mv      t0, s7
    li      t1, -1
53: beqz    t0, 54f
    srli    t0, t0, 1
    addi    t1, t1, 1
    j       53b
54: addi    t1, t1, -6
    sd      t1, SrCtx_levels(s4)
    li      a0, SR_JOB_AREA                 # its area: the zero hashes and a hash input
    add     a0, s4, a0
    sd      a0, SrCtx_area(s4)
    mv      a1, s5
    li      a2, 41 * 32
    call    lantern_copy
    li      t0, SR_JOB_AREA + STATE_ROOT_HASH
    add     t0, s4, t0
    li      t1, 24 + 64
    sd      t1, 0(t0)
    li      t1, 24
    sd      t1, 8(t0)
    li      t1, 64
    sd      t1, 16(t0)
    li      t0, SR_JOB_SCRATCH              # its scratch
    add     t0, s4, t0
    li      t1, SR_JOB_BYTES - SR_JOB_SCRATCH
    sd      t1, 0(t0)
    sd      t0, SrCtx_scratch(s4)
    sd      t1, SrCtx_front(s4)
    addi    s10, s10, 1
    j       5b
6:  addi    a1, sp, L + SrCtx__mem          # the run
    ADDRESS t0, lantern_sr_job
    sd      t0, ShellJob_function(a1)
    sd      s9, ShellJob_context(a1)
    sd      s8, ShellJob_count(a1)
    ld      a0, SrCtx_pool(s1)
    CALL_GLOBAL lantern_shell_pool_run
    li      s10, 0
7:  bgeu    s10, s8, 8f
    li      t0, SR_JOB_BYTES
    mul     s4, s10, t0
    add     s4, s4, s9
    ld      t0, SrCtx_status(s4)
    bnez    t0, 71f
    addi    s10, s10, 1
    j       7b
71: mv      a0, s1                          # a failed job: the tree alone, from no leaves
    call    lantern_sr_clean
    ld      t0, SrCtx_front(s1)
    sd      t0, 0(s3)
    j       50f
8:  mv      a0, s1                          # then the upper levels
    ld      a1, SrCtx_levels(s9)
    call    lantern_sr_levels
    ld      t0, SrCtx_front(s1)
    sd      t0, 0(s3)
    j       60f
50: mv      a0, s1                          # alone: the leaves, then every level
    call    lantern_sr_leaves
    beqz    a0, 51f
    sd      a0, SrCtx_status(s1)            # a failure: the tree holds nothing
    mv      a0, s1
    call    lantern_sr_clean
    ld      a0, SrCtx_status(s1)
    LEAVE (SrCtx__mem + 32)
51: mv      a0, s1
    li      a1, 0
    call    lantern_sr_levels
60: mv      a0, s1
    call    lantern_sr_post
    li      a0, 0
    LEAVE (SrCtx__mem + 32)
END_FUNCTION lantern_sr_tree

# A job of lantern_sr_tree: the SrCtx of job a1 of the regions at a0, its leaves then its levels; its status in it. s1 the SrCtx.
LOCAL_FUNCTION lantern_sr_job
    ENTER 0
    li      t0, SR_JOB_BYTES
    mul     s1, a1, t0
    add     s1, s1, a0
    mv      a0, s1
    call    lantern_sr_leaves
    sd      a0, SrCtx_status(s1)
    bnez    a0, 9f
    mv      a0, s1
    li      a1, 0
    call    lantern_sr_levels
9:  li      a0, 0
    LEAVE 0
END_FUNCTION lantern_sr_job

/*
 * The leaves lo to hi of the SrCtx a0: a chunk, or an element's root, that differs from the last
 * root's is written and made dirty. a0 = 0, or a status of ssz_hash_tree_root. s1 the SrCtx, s2
 * the cache, s3 scratch, s4 data, s5 the area, s6 hi, s7 a leaf, s8 the level's nodes, s9 its
 * dirty bits, s10 the old count. Locals: L the tree.
 */
LOCAL_FUNCTION lantern_sr_leaves
    ENTER 16
    mv      s1, a0
    ld      t0, SrCtx_tree(s1)
    sd      t0, L(sp)
    ld      s2, SrCtx_cache(s1)
    ld      s3, SrCtx_scratch(s1)
    ld      s5, SrCtx_area(s1)
    ld      s4, SrCtx_data(s1)
    ld      s6, SrCtx_hi(s1)
    ld      s7, SrCtx_lo(s1)
    ld      s10, SrCtx_old(s1)
    ld      t1, CacheTree_nodes(t0)
    add     s8, s2, t1
    ld      t1, CacheTree_dirty(t0)
    add     s9, s2, t1
3:  bgeu    s7, s6, 20f
    slli    t1, s7, 5
    add     t1, s8, t1                      # the leaf
    ld      t0, SrCtx_elem(s1)
    beqz    t0, 10f
    slli    t2, s7, 5
    add     t2, s4, t2                      # the chunk; the last one padded
    addi    t3, s7, 1
    ld      t4, SrCtx_leaves(s1)
    bne     t3, t4, 5f
    ld      t3, SrCtx_bytes(s1)
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
10: ld      a3, L(sp)                       # an element and its copy
    ld      t0, CacheTree_copy(a3)
    mul     t2, s7, t0
    add     t3, s4, t2
    ld      t4, CacheTree_copies(a3)
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
    ld      t0, SrCtx_front(s1)
    sd      t0, 0(s3)
    ld      a0, SrCtx_desc(s1)
    mv      a1, t3
    mv      a2, s3
    mv      a3, t1
    CALL_GLOBAL ssz_hash_tree_root
    beqz    a0, 18f
    LEAVE 16
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
20: li      a0, 0
    LEAVE 16
END_FUNCTION lantern_sr_leaves

# The level of an SrCtx: s8 its nodes, s9 its dirty bits, s10 its capacity, s6 its nodes in use, s4 it, to the next.
.macro SR_UP
    slli    t0, s10, 5
    add     s8, s8, t0
    addi    t0, s10, 63
    srli    t0, t0, 6
    slli    t0, t0, 3
    add     s9, s9, t0
    addi    s10, s10, 1
    srli    s10, s10, 1
    addi    s6, s6, 1
    srli    s6, s6, 1
    addi    s4, s4, 1
.endm

/* lo and hi of the locals at L + 32 and L + 40 to the next level. */
.macro SR_UP_RANGE
    ld      t0, (L + 32)(sp)
    srli    t0, t0, 1
    sd      t0, (L + 32)(sp)
    ld      t0, (L + 40)(sp)
    addi    t0, t0, 1
    srli    t0, t0, 1
    sd      t0, (L + 40)(sp)
.endm

/*
 * From level a1 of the SrCtx a0, level by level up to its `levels`, the parents of dirty nodes
 * of its range lo to hi. s1 the SrCtx, s2 the cache, s3 the last level, s4 the level, s5 the area,
 * s6 the level's nodes in use, s7 a word, s8 the level's nodes, s9 its dirty bits, s10 its
 * capacity. Locals: L the next level's nodes, L+8 its dirty bits, L+16 a word, L+24 a parent,
 * L+32 lo, L+40 hi, L+48 the words' end, L+56 the first level.
 */
LOCAL_FUNCTION lantern_sr_levels
    ENTER 64
    mv      s1, a0
    sd      a1, (L + 56)(sp)
    ld      t1, SrCtx_tree(s1)
    ld      s2, SrCtx_cache(s1)
    ld      s5, SrCtx_area(s1)
    ld      s3, SrCtx_levels(s1)
    ld      t0, CacheTree_nodes(t1)
    add     s8, s2, t0
    ld      t0, CacheTree_dirty(t1)
    add     s9, s2, t0
    ld      s10, CacheTree_capacity(t1)
    ld      s6, SrCtx_leaves(s1)
    ld      t0, SrCtx_lo(s1)
    sd      t0, (L + 32)(sp)
    ld      t0, SrCtx_hi(s1)
    sd      t0, (L + 40)(sp)
    li      s4, 0
1:  ld      t0, (L + 56)(sp)                # up to the first level
    bgeu    s4, t0, 22f
    SR_UP
    SR_UP_RANGE
    j       1b
22: li      t0, 1
    bleu    s6, t0, 30f
    bgeu    s4, s3, 30f
    slli    t0, s10, 5
    add     t0, s8, t0
    sd      t0, L(sp)
    addi    t1, s10, 63
    srli    t1, t1, 6
    slli    t1, t1, 3
    add     t1, s9, t1
    sd      t1, (L + 8)(sp)
    ld      t0, (L + 32)(sp)                # the words of the range
    srli    s7, t0, 6
    ld      t0, (L + 40)(sp)
    addi    t0, t0, 63
    srli    t0, t0, 6
    addi    t1, s6, 63
    srli    t1, t1, 6
    bleu    t0, t1, 221f
    mv      t0, t1
221: sd     t0, (L + 48)(sp)
23: ld      t0, (L + 48)(sp)
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
    sd      t2, (L + 16)(sp)
    sd      t4, (L + 24)(sp)
    slli    a0, t4, 6                       # the left child
    add     a0, s8, a0
    slli    t5, t4, 1
    addi    t5, t5, 1
    slli    a1, t5, 5                       # the right child, or the zero hash past the level
    add     a1, s8, a1
    bltu    t5, s6, 26f
    slli    a1, s4, 5
    add     a1, s5, a1
26: ld      a2, L(sp)
    slli    t5, t4, 5
    add     a2, a2, t5
    call    lantern_sr_hash
    ld      t4, (L + 24)(sp)                # the parent is dirty
    ld      t0, (L + 8)(sp)
    srli    t1, t4, 6
    slli    t1, t1, 3
    add     t0, t0, t1
    ld      t1, 0(t0)
    li      t2, 1
    sll     t2, t2, t4
    or      t1, t1, t2
    sd      t1, 0(t0)
    ld      t2, (L + 16)(sp)
    j       24b
28: addi    s7, s7, 1
    j       23b
29: SR_UP
    SR_UP_RANGE
    j       22b
30: LEAVE 64
END_FUNCTION lantern_sr_levels

/*
 * The root of the SrCtx a0 from its top: up to the limit's depth with zero hashes, the length mixed
 * in for a list, to out; the tree's count becomes its leaves. s1 the SrCtx, s2 the cache, s4 the
 * level, s5 the area, s6 the nodes in use, s8 the level's nodes, s9 its dirty bits, s10 its capacity.
 */
LOCAL_FUNCTION lantern_sr_post
    ENTER 0
    mv      s1, a0
    ld      t1, SrCtx_tree(s1)
    ld      s2, SrCtx_cache(s1)
    ld      s5, SrCtx_area(s1)
    ld      t0, CacheTree_nodes(t1)
    add     s8, s2, t0
    ld      t0, CacheTree_dirty(t1)
    add     s9, s2, t0
    ld      s10, CacheTree_capacity(t1)
    ld      s6, SrCtx_leaves(s1)
    li      s4, 0
1:  li      t0, 1                           # the top
    bleu    s6, t0, 2f
    SR_UP
    j       1b
2:  sd      zero, 0(s9)                     # the top's bit
    ld      t0, SrCtx_out(s1)
    bnez    s6, 31f
    ld      t1, SrCtx_depth(s1)             # no leaves: the zero hash of the limit's depth
    slli    t1, t1, 5
    add     t1, s5, t1
    COPY32  t0, t1
    j       33f
31: COPY32  t0, s8
32: ld      t1, SrCtx_depth(s1)             # up to the limit's depth
    bgeu    s4, t1, 33f
    ld      a0, SrCtx_out(s1)
    slli    a1, s4, 5
    add     a1, s5, a1
    mv      a2, a0
    call    lantern_sr_hash
    addi    s4, s4, 1
    j       32b
33: ld      t0, SrCtx_list(s1)              # a list: mix_in_length
    beqz    t0, 34f
    li      a1, STATE_ROOT_CHUNK
    add     a1, s5, a1
    ld      t0, SrCtx_count(s1)
    sd      t0, 0(a1)
    sd      zero, 8(a1)
    sd      zero, 16(a1)
    sd      zero, 24(a1)
    ld      a0, SrCtx_out(s1)
    mv      a2, a0
    call    lantern_sr_hash
34: ld      t0, SrCtx_leaves(s1)
    ld      t1, SrCtx_tree(s1)
    sd      t0, CacheTree_count(t1)
    LEAVE 0
END_FUNCTION lantern_sr_post

# After a failure: the tree of the SrCtx a0 holds nothing, every dirty bit of each level 0. A leaf; uses t0-t4.
LOCAL_FUNCTION lantern_sr_clean
    UNWIND_END_PROLOGUE
    ld      t0, SrCtx_tree(a0)
    ld      t1, SrCtx_cache(a0)
    sd      zero, CacheTree_count(t0)
    sd      zero, SrCtx_old(a0)
    ld      t2, CacheTree_dirty(t0)
    add     t2, t1, t2
    ld      t3, CacheTree_capacity(t0)
1:  addi    t4, t3, 63
    srli    t4, t4, 6
2:  beqz    t4, 3f
    sd      zero, 0(t2)
    addi    t2, t2, 8
    addi    t4, t4, -1
    j       2b
3:  li      t1, 1
    bleu    t3, t1, 9f
    addi    t3, t3, 1
    srli    t3, t3, 1
    j       1b
9:  ret
END_FUNCTION lantern_sr_clean
.endif

# The root of each field of the state into the leaves of the area, in field order: s1 state, s2 cache, s3
# scratch, s5 the area, s10 the size of the front; s6, s7 and s8 are its own. To 90f for a tree past its
# capacity, 98f for a refusal of ssz.
.macro SR_FIELD_ROOTS pool
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
.ifc \pool, none
    li      t6, 0
.else
    ld      t6, \pool(sp)
.endif
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
SPEC_LEAF state_root
    li      a4, 0
    j       lantern_sr_root
SPEC_END state_root

# (state, cache, scratch, out, pool): state.md. As lantern_state_root, with the jobs of lantern_sr_tree on pool.
SPEC_LEAF state_root_pool
    j       lantern_sr_root
SPEC_END state_root_pool

/*
 * lantern_state_root with pool a4, or 0. Its registers as before, and locals: L the scratch size on
 * entry, L+8 the pool.
 */
LOCAL_FUNCTION lantern_sr_root
    ENTER 16
    sd      a4, (L + 8)(sp)
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
    SR_FIELD_ROOTS (L + 8)
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
END_FUNCTION lantern_sr_root

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
    SR_FIELD_ROOTS none
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
