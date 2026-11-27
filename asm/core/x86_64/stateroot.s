/*
 * The hash tree root of a state from a StateCache, x86-64. Requirements: docs/reference/state.md.
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
 * Lays out the trees of the StateCache table for rdi validators, into cache rsi when it is
 * not 0; rax = the bytes of the cache. rbx validators, rbp cache, r12 the table, r13 the offset of
 * the next tree's bytes, r14 the tree, r15 its header, S7 its capacity, S8 its copy bytes.
 */
LOCAL_FUNCTION lantern_sr_layout
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    ADDRESS %r12, state_cache_trees
    mov     $STATE_CACHE_FIXED, %r13d
    xor     %r14d, %r14d
1:  mov     8(%r12), %rax                   # the constant, or ceil(validators / divisor)
    mov     (%r12), %rcx
    test    %rcx, %rcx
    jz      2f
    lea     -1(%rbx,%rcx), %rax
    xor     %edx, %edx
    div     %rcx
2:  mov     %rax, S7(%rsp)
    mov     16(%r12), %rax
    mov     %rax, S8(%rsp)
    imul    $CacheTree__mem, %r14, %r15
    lea     StateCache_trees(%rbp,%r15), %r15
    test    %rbp, %rbp
    jz      3f
    mov     S7(%rsp), %rax
    mov     %rax, CacheTree_capacity(%r15)
    movq    $0, CacheTree_count(%r15)
    mov     %r13, CacheTree_nodes(%r15)
    mov     S8(%rsp), %rax
    mov     %rax, CacheTree_copy(%r15)
3:  mov     S7(%rsp), %rcx                  # nodes and dirty words of each level
    xor     %edx, %edx
    xor     %r8d, %r8d
4:  add     %rcx, %rdx
    lea     63(%rcx), %rax
    shr     $6, %rax
    add     %rax, %r8
    cmp     $1, %rcx
    jbe     5f
    inc     %rcx
    shr     $1, %rcx
    jmp     4b
5:  shl     $5, %rdx
    add     %rdx, %r13
    test    %rbp, %rbp
    jz      7f
    mov     %r13, CacheTree_dirty(%r15)
    lea     (%rbp,%r13), %rdi               # every dirty bit 0
    mov     %r8, %rcx
    xor     %eax, %eax
    rep stosq
7:  lea     (%r13,%r8,8), %r13
    xor     %eax, %eax
    cmpq    $0, S8(%rsp)
    je      8f
    mov     %r13, %rax
    mov     S7(%rsp), %rcx
    imul    S8(%rsp), %rcx
    add     %rcx, %r13
8:  test    %rbp, %rbp
    jz      9f
    mov     %rax, CacheTree_copies(%r15)
9:  add     $24, %r12
    inc     %r14
    cmp     $STATE_CACHE_TREES, %r14
    jb      1b
    mov     %r13, %rax
    LEAVE 16
END_FUNCTION lantern_sr_layout

/* Locals: rsp+0 size. */
SPEC_FUNCTION state_cache_size
    FRAME 16
    mov     %rsi, (%rsp)
    mov     (%rdi), %rdi
    xor     %esi, %esi
    call    lantern_sr_layout
    mov     (%rsp), %rsi
    mov     %rax, (%rsi)
    xor     %eax, %eax
    UNFRAME 16
SPEC_END state_cache_size

/* Locals: rsp+0 cache, rsp+8 validators. */
SPEC_FUNCTION state_cache_init
    FRAME 16
    mov     (%rdi), %rdi
    mov     %rsi, (%rsp)
    mov     %rdi, 8(%rsp)
    xor     %esi, %esi
    call    lantern_sr_layout
    mov     (%rsp), %rsi
    cmp     %rax, StateCache_size(%rsi)
    jb      9f
    mov     8(%rsp), %rdi
    mov     %rdi, StateCache_validators(%rsi)
    movq    $0, StateCache_pool(%rsi)
    call    lantern_sr_layout
    xor     %eax, %eax
    UNFRAME 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    UNFRAME 16
SPEC_END state_cache_init

.if FORK > FORK_PHASE0
/* SHA-256 of the 32 bytes at rdi and the 32 bytes at rsi, to rdx, which may be rdi or rsi. r14 the area. */
LOCAL_FUNCTION lantern_sr_hash
    FRAME 16
    mov     %rdx, (%rsp)
    lea     (STATE_ROOT_HASH + 24)(%r14), %rax
    COPY32  %rax, %rdi
    add     $32, %rax
    COPY32  %rax, %rsi
    lea     STATE_ROOT_HASH(%r14), %rdi
    mov     (%rsp), %rsi
    CALL_GLOBAL crypto_sha256
    UNFRAME 16
END_FUNCTION lantern_sr_hash

/* The zero hash of each depth 0 to 40 in the area at r14. rbx the next, rbp the hashes left. */
LOCAL_FUNCTION lantern_sr_zeros
    ENTER 16
    mov     %r14, %rbx
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, (%rbx)
    movdqu  %xmm0, 16(%rbx)
    mov     $40, %ebp
1:  mov     %rbx, %rdi
    mov     %rbx, %rsi
    lea     32(%rbx), %rdx
    call    lantern_sr_hash
    add     $32, %rbx
    dec     %rbp
    jnz     1b
    LEAVE 16
END_FUNCTION lantern_sr_zeros

/*
 * The root of a field from tree rdi (a CacheTree): data rsi, count rdx elements, rcx the bytes
 * of an element of a basic type, or the descriptor of a container type (an address above 4095),
 * r8 the limit's depth + 256 for a list (mixed with the count), the root to r9, rax a ShellPool
 * or 0. rax = 0, 1 when the leaves pass the capacity, or a status of ssz_hash_tree_root. rbp the
 * cache, r12 scratch with its front's size set, r14 the area. With a pool and at least two jobs of
 * leaves, jobs of lantern_sr_job hash ranges of the leaves and their lower levels at once, each in
 * a region of SR_JOB_BYTES at the end of the front; a failed job makes the tree's work start again
 * alone. rbx the SrCtx, r13 a job's SrCtx, r15 the leaves, S7 the jobs' leaves, S8 the jobs, S9
 * the first region, S10 a job. Locals: L the SrCtx, L+SrCtx__mem a ShellJob.
 */
LOCAL_FUNCTION lantern_sr_tree
    ENTER (SrCtx__mem + 32)
    mov     %rax, (L + SrCtx_pool)(%rsp)
    lea     L(%rsp), %rbx
    mov     %rdi, SrCtx_tree(%rbx)
    mov     %rsi, SrCtx_data(%rbx)
    mov     %rdx, SrCtx_count(%rbx)
    xor     %eax, %eax
    cmp     $4096, %rcx
    jae     1f
    mov     %rcx, %rax
    xor     %ecx, %ecx
1:  mov     %rax, SrCtx_elem(%rbx)
    mov     %rcx, SrCtx_desc(%rbx)
    movzbl  %r8b, %eax
    mov     %rax, SrCtx_depth(%rbx)
    shr     $8, %r8
    mov     %r8, SrCtx_list(%rbx)
    mov     %r9, SrCtx_out(%rbx)
    mov     (%r12), %rax
    mov     %rax, SrCtx_front(%rbx)
    mov     %rdx, %rax
    imulq   SrCtx_elem(%rbx), %rax
    mov     %rax, SrCtx_bytes(%rbx)
    mov     %rdx, %r15                      # the leaves: elements, or chunks
    cmpq    $0, SrCtx_elem(%rbx)
    je      2f
    lea     31(%rax), %r15
    shr     $5, %r15
2:  mov     %r15, SrCtx_leaves(%rbx)
    mov     %rbp, SrCtx_cache(%rbx)
    mov     %r12, SrCtx_scratch(%rbx)
    mov     %r14, SrCtx_area(%rbx)
    movq    $0, SrCtx_status(%rbx)
    movq    $0, SrCtx_lo(%rbx)
    mov     %r15, SrCtx_hi(%rbx)
    movq    $64, SrCtx_levels(%rbx)
    cmp     CacheTree_capacity(%rdi), %r15
    jbe     3f
    mov     $1, %eax
    LEAVE (SrCtx__mem + 32)
3:  mov     CacheTree_count(%rdi), %rax
    mov     %rax, SrCtx_old(%rbx)
    cmp     %rax, %r15                      # fewer leaves than the last root: the last one is dirty
    jae     4f
    test    %r15, %r15
    jz      4f
    mov     CacheTree_dirty(%rdi), %rax
    add     %rbp, %rax
    lea     -1(%r15), %rcx
    mov     %rcx, %rdx
    shr     $6, %rdx
    mov     (%rax,%rdx,8), %r8
    bts     %rcx, %r8
    mov     %r8, (%rax,%rdx,8)
4:  cmpq    $0, SrCtx_pool(%rbx)            # the jobs: 2 to SR_JOBS_MAX of a power of two of leaves
    je      50f
    lea     (SR_JOBS_MAX - 1)(%r15), %rax
    shr     $SR_JOBS_SHIFT, %rax
    mov     $SR_JOB_MIN, %ecx
    cmp     %rcx, %rax
    jbe     5f
    dec     %rax
    bsr     %rax, %rcx
    inc     %ecx
    mov     $1, %eax
    shl     %cl, %rax
    mov     %rax, %rcx
5:  mov     %rcx, S7(%rsp)
    lea     -1(%r15,%rcx), %rax
    xor     %edx, %edx
    div     %rcx
    mov     %rax, S8(%rsp)
    cmp     $2, %rax
    jb      50f
    imul    $SR_JOB_BYTES, %rax, %rax       # their regions at the end of the front
    mov     SrCtx_front(%rbx), %rcx
    cmp     %rcx, %rax
    ja      50f
    sub     %rax, %rcx
    add     %r12, %rcx
    mov     %rcx, S9(%rsp)
    movq    $0, S10(%rsp)
6:  mov     S10(%rsp), %rax
    cmp     S8(%rsp), %rax
    jae     7f
    imul    $SR_JOB_BYTES, %rax, %r13
    add     S9(%rsp), %r13
    mov     %r13, %rdi
    mov     %rbx, %rsi
    mov     $SrCtx__mem, %edx
    call    lantern_copy
    mov     S10(%rsp), %rax                 # its range of leaves and its levels
    imul    S7(%rsp), %rax
    mov     %rax, SrCtx_lo(%r13)
    add     S7(%rsp), %rax
    cmp     %r15, %rax
    cmova   %r15, %rax
    mov     %rax, SrCtx_hi(%r13)
    bsr     S7(%rsp), %rax
    sub     $6, %rax
    mov     %rax, SrCtx_levels(%r13)
    lea     SR_JOB_AREA(%r13), %rdi         # its area: the zero hashes and a hash input
    mov     %rdi, SrCtx_area(%r13)
    mov     %r14, %rsi
    mov     $(41 * 32), %edx
    call    lantern_copy
    movq    $(24 + 64), (SR_JOB_AREA + STATE_ROOT_HASH)(%r13)
    movq    $24, (SR_JOB_AREA + STATE_ROOT_HASH + 8)(%r13)
    movq    $64, (SR_JOB_AREA + STATE_ROOT_HASH + 16)(%r13)
    lea     SR_JOB_SCRATCH(%r13), %rax      # its scratch
    movq    $(SR_JOB_BYTES - SR_JOB_SCRATCH), (%rax)
    mov     %rax, SrCtx_scratch(%r13)
    movq    $(SR_JOB_BYTES - SR_JOB_SCRATCH), SrCtx_front(%r13)
    incq    S10(%rsp)
    jmp     6b
7:  lea     (L + SrCtx__mem)(%rsp), %rsi    # the run
    lea     lantern_sr_job(%rip), %rax
    mov     %rax, ShellJob_function(%rsi)
    mov     S9(%rsp), %rax
    mov     %rax, ShellJob_context(%rsi)
    mov     S8(%rsp), %rax
    mov     %rax, ShellJob_count(%rsi)
    mov     SrCtx_pool(%rbx), %rdi
    CALL_GLOBAL lantern_shell_pool_run
    movq    $0, S10(%rsp)
71: mov     S10(%rsp), %rax
    cmp     S8(%rsp), %rax
    jae     8f
    imul    $SR_JOB_BYTES, %rax, %r13
    add     S9(%rsp), %r13
    cmpq    $0, SrCtx_status(%r13)
    jne     72f
    incq    S10(%rsp)
    jmp     71b
72: mov     %rbx, %rdi                      # a failed job: the tree alone, from no leaves
    call    lantern_sr_clean
    mov     SrCtx_front(%rbx), %rax
    mov     %rax, (%r12)
    jmp     50f
8:  mov     %rbx, %rdi                      # then the upper levels
    mov     S9(%rsp), %rax
    mov     SrCtx_levels(%rax), %rsi
    call    lantern_sr_levels
    mov     SrCtx_front(%rbx), %rax
    mov     %rax, (%r12)
    jmp     60f
50: mov     %rbx, %rdi                      # alone: the leaves, then every level
    call    lantern_sr_leaves
    test    %rax, %rax
    jz      51f
    mov     %rax, SrCtx_status(%rbx)        # a failure: the tree holds nothing
    mov     %rbx, %rdi
    call    lantern_sr_clean
    mov     SrCtx_status(%rbx), %rax
    LEAVE (SrCtx__mem + 32)
51: mov     %rbx, %rdi
    xor     %esi, %esi
    call    lantern_sr_levels
60: mov     %rbx, %rdi
    call    lantern_sr_post
    xor     %eax, %eax
    LEAVE (SrCtx__mem + 32)
END_FUNCTION lantern_sr_tree

# A job of lantern_sr_tree: the SrCtx of job rsi of the regions at rdi, its leaves then its levels; its status in it. rbx the SrCtx.
LOCAL_FUNCTION lantern_sr_job
    ENTER 0
    imul    $SR_JOB_BYTES, %rsi, %rbx
    add     %rdi, %rbx
    mov     %rbx, %rdi
    call    lantern_sr_leaves
    mov     %rax, SrCtx_status(%rbx)
    test    %rax, %rax
    jnz     9f
    mov     %rbx, %rdi
    xor     %esi, %esi
    call    lantern_sr_levels
9:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_sr_job

/*
 * The leaves lo to hi of the SrCtx rdi: a chunk, or an element's root, that differs from the last
 * root's is written and made dirty. rax = 0, or a status of ssz_hash_tree_root. rbx the SrCtx, rbp
 * the cache, r12 scratch, r13 data, r14 the area, r15 hi, S7 a leaf, S8 the level's nodes, S9 its
 * dirty bits, S10 the old count. Locals: L the tree.
 */
LOCAL_FUNCTION lantern_sr_leaves
    ENTER 16
    mov     %rdi, %rbx
    mov     SrCtx_tree(%rbx), %rax
    mov     %rax, L(%rsp)
    mov     SrCtx_cache(%rbx), %rbp
    mov     SrCtx_scratch(%rbx), %r12
    mov     SrCtx_area(%rbx), %r14
    mov     SrCtx_data(%rbx), %r13
    mov     SrCtx_hi(%rbx), %r15
    mov     SrCtx_lo(%rbx), %rcx
    mov     %rcx, S7(%rsp)
    mov     SrCtx_old(%rbx), %rcx
    mov     %rcx, S10(%rsp)
    mov     CacheTree_nodes(%rax), %rcx
    add     %rbp, %rcx
    mov     %rcx, S8(%rsp)
    mov     CacheTree_dirty(%rax), %rcx
    add     %rbp, %rcx
    mov     %rcx, S9(%rsp)
4:  mov     S7(%rsp), %rcx
    cmp     %r15, %rcx
    jae     20f
    mov     %rcx, %rdi                      # the leaf
    shl     $5, %rdi
    add     S8(%rsp), %rdi
    cmpq    $0, SrCtx_elem(%rbx)
    je      10f
    mov     %rcx, %rsi                      # the chunk; the last one padded
    shl     $5, %rsi
    add     %r13, %rsi
    lea     1(%rcx), %rax
    cmp     SrCtx_leaves(%rbx), %rax
    jne     6f
    mov     SrCtx_bytes(%rbx), %rax
    and     $31, %eax
    jz      6f
    lea     STATE_ROOT_CHUNK(%r14), %rdx
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, (%rdx)
    movdqu  %xmm0, 16(%rdx)
    xor     %r8d, %r8d
5:  movzbl  (%rsi,%r8), %r9d
    mov     %r9b, (%rdx,%r8)
    inc     %r8
    cmp     %rax, %r8
    jb      5b
    mov     %rdx, %rsi
6:  cmp     S10(%rsp), %rcx                 # a leaf of the last root stays when the chunk does
    jae     7f
    NE32    %rsi, %rdi, 7f
    jmp     19f
7:  COPY32  %rdi, %rsi
    jmp     18f
10: mov     L(%rsp), %rax                   # an element and its copy
    mov     CacheTree_copy(%rax), %r8
    mov     CacheTree_copies(%rax), %rdx
    mov     %rcx, %rax
    imul    %r8, %rax
    lea     (%r13,%rax), %rsi
    add     %rbp, %rdx
    add     %rax, %rdx
    cmp     S10(%rsp), %rcx
    jae     12f
    xor     %eax, %eax
11: mov     (%rsi,%rax), %r9
    cmp     (%rdx,%rax), %r9
    jne     12f
    add     $8, %rax
    cmp     %r8, %rax
    jb      11b
    jmp     19f
12: xor     %eax, %eax                      # the copy takes the element, the leaf its root
13: mov     (%rsi,%rax), %r9
    mov     %r9, (%rdx,%rax)
    add     $8, %rax
    cmp     %r8, %rax
    jb      13b
    mov     SrCtx_front(%rbx), %rax
    mov     %rax, (%r12)
    mov     %rdi, %rcx
    mov     SrCtx_desc(%rbx), %rdi
    mov     %r12, %rdx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jz      18f
    LEAVE 16
18: mov     S7(%rsp), %rcx                  # the leaf is dirty
    mov     S9(%rsp), %rax
    mov     %rcx, %rdx
    shr     $6, %rdx
    mov     (%rax,%rdx,8), %r8
    bts     %rcx, %r8
    mov     %r8, (%rax,%rdx,8)
19: incq    S7(%rsp)
    jmp     4b
20: xor     %eax, %eax
    LEAVE 16
END_FUNCTION lantern_sr_leaves

# The level of an SrCtx: S8 its nodes, S9 its dirty bits, S10 its capacity, r15 its nodes in use, r13 it, to the next.
.macro SR_UP
    mov     S10(%rsp), %rax
    shl     $5, %rax
    add     %rax, S8(%rsp)
    mov     S10(%rsp), %rax
    add     $63, %rax
    shr     $6, %rax
    shl     $3, %rax
    add     %rax, S9(%rsp)
    mov     S10(%rsp), %rax
    inc     %rax
    shr     $1, %rax
    mov     %rax, S10(%rsp)
    inc     %r15
    shr     $1, %r15
    inc     %r13
.endm

/*
 * From level rsi of the SrCtx rdi, level by level up to its `levels`, the parents of dirty nodes
 * of its range lo to hi. rbx the SrCtx, rbp the cache, r12 the last level, r13 the level, r14 the
 * area, r15 the level's nodes in use, S7 a word, S8 the level's nodes, S9 its dirty bits, S10 its
 * capacity. Locals: L the next level's nodes, L+8 its dirty bits, L+16 a word, L+24 a parent,
 * L+32 lo, L+40 hi, L+48 the words' end, L+56 the first level.
 */
LOCAL_FUNCTION lantern_sr_levels
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, (L + 56)(%rsp)
    mov     SrCtx_tree(%rbx), %rax
    mov     SrCtx_cache(%rbx), %rbp
    mov     SrCtx_area(%rbx), %r14
    mov     SrCtx_levels(%rbx), %r12
    mov     CacheTree_nodes(%rax), %rcx
    add     %rbp, %rcx
    mov     %rcx, S8(%rsp)
    mov     CacheTree_dirty(%rax), %rcx
    add     %rbp, %rcx
    mov     %rcx, S9(%rsp)
    mov     CacheTree_capacity(%rax), %rcx
    mov     %rcx, S10(%rsp)
    mov     SrCtx_leaves(%rbx), %r15
    mov     SrCtx_lo(%rbx), %rax
    mov     %rax, (L + 32)(%rsp)
    mov     SrCtx_hi(%rbx), %rax
    mov     %rax, (L + 40)(%rsp)
    xor     %r13d, %r13d
1:  cmp     (L + 56)(%rsp), %r13            # up to the first level
    jae     22f
    SR_UP
    shrq    (L + 32)(%rsp)
    incq    (L + 40)(%rsp)
    shrq    (L + 40)(%rsp)
    jmp     1b
22: cmp     $1, %r15
    jbe     30f
    cmp     %r12, %r13
    jae     30f
    mov     S10(%rsp), %rax
    shl     $5, %rax
    add     S8(%rsp), %rax
    mov     %rax, L(%rsp)
    mov     S10(%rsp), %rax
    add     $63, %rax
    shr     $6, %rax
    shl     $3, %rax
    add     S9(%rsp), %rax
    mov     %rax, (L + 8)(%rsp)
    mov     (L + 32)(%rsp), %rax            # the words of the range
    shr     $6, %rax
    mov     %rax, S7(%rsp)
    mov     (L + 40)(%rsp), %rax
    add     $63, %rax
    shr     $6, %rax
    lea     63(%r15), %rcx
    shr     $6, %rcx
    cmp     %rcx, %rax
    cmova   %rcx, %rax
    mov     %rax, (L + 48)(%rsp)
23: mov     S7(%rsp), %rcx
    cmp     (L + 48)(%rsp), %rcx
    jae     29f
    mov     S9(%rsp), %rax
    mov     (%rax,%rcx,8), %rdx
    test    %rdx, %rdx
    jz      28f
    movq    $0, (%rax,%rcx,8)
24: test    %rdx, %rdx
    jz      28f
    bsf     %rdx, %rcx                      # the lowest dirty bit
    btr     %rcx, %rdx
    test    $1, %cl
    jnz     25f
    lea     1(%rcx), %rax                   # an even node covers its sibling
    btr     %rax, %rdx
25: mov     S7(%rsp), %rax
    shl     $6, %rax
    add     %rax, %rcx
    shr     $1, %rcx                        # the parent
    mov     %rdx, (L + 16)(%rsp)
    mov     %rcx, (L + 24)(%rsp)
    mov     %rcx, %rdi                      # the left child
    shl     $6, %rdi
    add     S8(%rsp), %rdi
    lea     1(%rcx,%rcx), %rax
    mov     %rax, %rsi                      # the right child, or the zero hash past the level
    shl     $5, %rsi
    add     S8(%rsp), %rsi
    cmp     %r15, %rax
    jb      26f
    mov     %r13, %rsi
    shl     $5, %rsi
    add     %r14, %rsi
26: mov     %rcx, %rdx
    shl     $5, %rdx
    add     L(%rsp), %rdx
    call    lantern_sr_hash
    mov     (L + 24)(%rsp), %rcx            # the parent is dirty
    mov     (L + 8)(%rsp), %rax
    mov     %rcx, %rdx
    shr     $6, %rdx
    mov     (%rax,%rdx,8), %r8
    bts     %rcx, %r8
    mov     %r8, (%rax,%rdx,8)
    mov     (L + 16)(%rsp), %rdx
    jmp     24b
28: incq    S7(%rsp)
    jmp     23b
29: SR_UP
    shrq    (L + 32)(%rsp)
    incq    (L + 40)(%rsp)
    shrq    (L + 40)(%rsp)
    jmp     22b
30: LEAVE 64
END_FUNCTION lantern_sr_levels

/*
 * The root of the SrCtx rdi from its top: up to the limit's depth with zero hashes, the length mixed
 * in for a list, to out; the tree's count becomes its leaves. rbx the SrCtx, rbp the cache, r13 the
 * level, r14 the area, r15 the nodes in use, S8 the level's nodes, S9 its dirty bits, S10 its capacity.
 */
LOCAL_FUNCTION lantern_sr_post
    ENTER 0
    mov     %rdi, %rbx
    mov     SrCtx_tree(%rbx), %rax
    mov     SrCtx_cache(%rbx), %rbp
    mov     SrCtx_area(%rbx), %r14
    mov     CacheTree_nodes(%rax), %rcx
    add     %rbp, %rcx
    mov     %rcx, S8(%rsp)
    mov     CacheTree_dirty(%rax), %rcx
    add     %rbp, %rcx
    mov     %rcx, S9(%rsp)
    mov     CacheTree_capacity(%rax), %rcx
    mov     %rcx, S10(%rsp)
    mov     SrCtx_leaves(%rbx), %r15
    xor     %r13d, %r13d
1:  cmp     $1, %r15                        # the top
    jbe     2f
    SR_UP
    jmp     1b
2:  mov     S9(%rsp), %rax                  # the top's bit
    movq    $0, (%rax)
    mov     SrCtx_out(%rbx), %rdi
    test    %r15, %r15
    jnz     31f
    mov     SrCtx_depth(%rbx), %rax         # no leaves: the zero hash of the limit's depth
    shl     $5, %rax
    add     %r14, %rax
    COPY32  %rdi, %rax
    jmp     33f
31: mov     S8(%rsp), %rax
    COPY32  %rdi, %rax
32: cmp     SrCtx_depth(%rbx), %r13         # up to the limit's depth
    jae     33f
    mov     SrCtx_out(%rbx), %rdi
    mov     %r13, %rsi
    shl     $5, %rsi
    add     %r14, %rsi
    mov     %rdi, %rdx
    call    lantern_sr_hash
    inc     %r13
    jmp     32b
33: cmpq    $0, SrCtx_list(%rbx)            # a list: mix_in_length
    je      34f
    lea     STATE_ROOT_CHUNK(%r14), %rsi
    mov     SrCtx_count(%rbx), %rax
    mov     %rax, (%rsi)
    movq    $0, 8(%rsi)
    movq    $0, 16(%rsi)
    movq    $0, 24(%rsi)
    mov     SrCtx_out(%rbx), %rdi
    mov     %rdi, %rdx
    call    lantern_sr_hash
34: mov     SrCtx_leaves(%rbx), %rax
    mov     SrCtx_tree(%rbx), %rcx
    mov     %rax, CacheTree_count(%rcx)
    LEAVE 0
END_FUNCTION lantern_sr_post

# After a failure: the tree of the SrCtx rdi holds nothing, every dirty bit of each level 0. A leaf; uses rcx, r8-r11.
LOCAL_FUNCTION lantern_sr_clean
    UNWIND_END_PROLOGUE
    mov     SrCtx_tree(%rdi), %r8
    mov     SrCtx_cache(%rdi), %r9
    movq    $0, CacheTree_count(%r8)
    movq    $0, SrCtx_old(%rdi)
    mov     CacheTree_dirty(%r8), %r10
    add     %r9, %r10
    mov     CacheTree_capacity(%r8), %r11
1:  lea     63(%r11), %rcx
    shr     $6, %rcx
2:  test    %rcx, %rcx
    jz      3f
    movq    $0, (%r10)
    add     $8, %r10
    dec     %rcx
    jmp     2b
3:  cmp     $1, %r11
    jbe     9f
    inc     %r11
    shr     $1, %r11
    jmp     1b
9:  ret
END_FUNCTION lantern_sr_clean
.endif

# The root of each field of the state into the leaves of the area, in field order: rbx state, rbp cache,
# r12 scratch, r14 the area, S10 the size of the front; r15, S7 and S8 are its own. To 90f for a tree past
# its capacity, 98f for a refusal of ssz.
.macro SR_FIELD_ROOTS pool
    ADDRESS %r15, state_root_fields
    movq    $SR_COUNT, S7(%rsp)
    lea     STATE_ROOT_LEAVES(%r14), %rax
    mov     %rax, S8(%rsp)
1:  cmpq    $(0), S7(%rsp)
    je      49f
    mov     S10(%rsp), %rax
    mov     %rax, (%r12)
    mov     (%r15), %rax                    # kind
    mov     8(%r15), %rsi
    add     %rbx, %rsi                      # the field
    cmp     $SR_LEAF, %rax
    jne     3f
    mov     S8(%rsp), %rdi
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, (%rdi)
    movdqu  %xmm0, 16(%rdi)
    mov     24(%r15), %rcx
    rep movsb
    jmp     40f
3:  cmp     $SR_TYPE, %rax
    je      4f
    cmp     $SR_NESTED, %rax
    jne     5f
    mov     (%rsi), %rsi                    # the nested value of the part
    add     %rbx, %rsi
4:  ADDRESS %rdi, state_root_fields
    add     24(%r15), %rdi
    mov     %r12, %rdx
    mov     S8(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     98f
    jmp     40f
5:  cmp     $SR_PVEC, %rax
    jne     6f
    mov     24(%r15), %rdx                  # the bytes, as elements of 1 byte; no length
    mov     $(1), %ecx
    mov     32(%r15), %r8
    jmp     8f
6:  mov     8(%rsi), %rdx                   # a list: its part
    mov     (%rsi), %rsi
    add     %rbx, %rsi
    mov     32(%r15), %r8
    or      $(256), %r8
    cmp     $SR_PLIST, %rax
    jne     7f
    mov     24(%r15), %rcx
    jmp     8f
7:  ADDRESS %rcx, state_root_fields         # containers of a descriptor
    add     24(%r15), %rcx
8:  mov     16(%r15), %rdi                  # its tree
    imul    $CacheTree__mem, %rdi, %rdi
    lea     StateCache_trees(%rbp,%rdi), %rdi
    mov     S8(%rsp), %r9
.ifc \pool, none
    xor     %eax, %eax
.else
    mov     \pool(%rsp), %rax
.endif
    call    lantern_sr_tree
    cmp     $(1), %rax
    je      90f
    test    %rax, %rax
    jnz     98f
40: add     $(40), %r15
    addq    $(32), S8(%rsp)
    decq    S7(%rsp)
    jmp     1b
49:
.endm

/*
 * rbx state, rbp cache, r12 scratch, r13 out, r14 the area at the end of scratch, r15 the field
 * record, S7 the fields left, S8 the field's root, S9 the scratch size on entry, S10 the size of
 * the front, which callees get.
 */
SPEC_LEAF state_root
    xor     %r8d, %r8d                      # the cache's pool, or none
    test    %rsi, %rsi
    jz      1f
    mov     StateCache_pool(%rsi), %r8
1:  jmp     lantern_sr_root
SPEC_END state_root

# (state, cache, scratch, out, pool): state.md. As lantern_state_root, with the jobs of lantern_sr_tree on pool.
SPEC_LEAF state_root_pool
    jmp     lantern_sr_root
SPEC_END state_root_pool

/*
 * lantern_state_root with pool r8, or 0. rbx state, rbp cache, r12 scratch, r13 out, r14 the area at
 * the end of scratch, r15 the field record, S7 the fields left, S8 the field's root, S9 the scratch size
 * on entry, S10 the size of the front, which callees get. Locals: L the pool.
 */
LOCAL_FUNCTION lantern_sr_root
    ENTER 16
    mov     %r8, L(%rsp)
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     (%r12), %rax
    mov     %rax, S9(%rsp)
.if FORK > FORK_PHASE0
    test    %rbp, %rbp
    jz      90f
    cmp     $LANTERN_SCRATCH_FIXED, %rax
    jb      99f
    sub     $STATE_ROOT_AREA, %rax
    mov     %rax, S10(%rsp)
    lea     (%r12,%rax), %r14
    movq    $(24 + 64), STATE_ROOT_HASH(%r14)   # the hash input: a ByteList of 64 bytes
    movq    $24, (STATE_ROOT_HASH + 8)(%r14)
    movq    $64, (STATE_ROOT_HASH + 16)(%r14)
    call    lantern_sr_zeros
    SR_FIELD_ROOTS L
50: lea     STATE_ROOT_LEAVES(%r14), %rdi   # zeros to the width, then merkleize
    pxor    %xmm0, %xmm0
    mov     $SR_COUNT, %ecx
51: cmp     $STATE_ROOT_WIDTH, %rcx
    jae     52f
    mov     %rcx, %rax
    shl     $5, %rax
    movdqu  %xmm0, (%rdi,%rax)
    movdqu  %xmm0, 16(%rdi,%rax)
    inc     %rcx
    jmp     51b
52: mov     $STATE_ROOT_WIDTH, %r15d
53: cmp     $1, %r15
    jbe     55f
    shr     $1, %r15
    movq    $0, S7(%rsp)
54: mov     S7(%rsp), %rax
    lea     STATE_ROOT_LEAVES(%r14), %rdx
    mov     %rax, %rdi
    shl     $6, %rdi
    add     %rdx, %rdi
    lea     32(%rdi), %rsi
    shl     $5, %rax
    add     %rax, %rdx
    call    lantern_sr_hash
    incq    S7(%rsp)
    cmp     %r15, S7(%rsp)
    jb      54b
    jmp     53b
55: lea     STATE_ROOT_LEAVES(%r14), %rax
    COPY32  %r13, %rax
    mov     S9(%rsp), %rax
    mov     %rax, (%r12)
    xor     %eax, %eax
    LEAVE 16
98: mov     S9(%rsp), %rcx
    mov     %rcx, (%r12)
    LEAVE 16
99: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
.endif
90: mov     S9(%rsp), %rax                  # ssz_hash_tree_root of the state
    mov     %rax, (%r12)
    ADDRESS %rdi, lantern_type_BeaconState
    mov     %rbx, %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    CALL_GLOBAL ssz_hash_tree_root
    LEAVE 16
END_FUNCTION lantern_sr_root

/*
 * rbx state, rbp cache, then the nodes of a level, r12 scratch, r13 out, r14 the area at the end of
 * scratch, r15 the leaf's index, S7 a node, S8 the next root of out, S9 the scratch size on entry,
 * S10 the size of the front, which callees get. Locals: L the field, L+8 the generalized index.
 */
SPEC_FUNCTION state_branch
    ENTER 16
.if FORK == FORK_PHASE0
    mov     $LANTERN_NO_STATE_ANSWER, %eax
    LEAVE 16
.else
    cmp     $LC_BRANCH_FINALIZED_ROOT, %rsi
    ja      97f
    mov     %rdi, %rbx
    mov     %rsi, L(%rsp)
    mov     %rdx, %rbp
    mov     %rcx, %r12
    mov     %r8, %r13
    mov     (%r12), %rax
    mov     %rax, S9(%rsp)
    lea     (STATE_ROOT_WIDTH + 22)(%rsi), %rcx # the generalized index: current_sync_committee is field 22, next 23
    cmp     $LC_BRANCH_FINALIZED_ROOT, %rsi
    jne     1f
    mov     $((STATE_ROOT_WIDTH + 20) * 2 + 1), %ecx    # finalized_checkpoint (field 20), then its root
1:  mov     %rcx, (L + 8)(%rsp)
    test    %rbp, %rbp
    jz      90f
    cmp     $LANTERN_SCRATCH_FIXED, %rax
    jb      99f
    sub     $STATE_ROOT_AREA, %rax
    mov     %rax, S10(%rsp)
    lea     (%r12,%rax), %r14
    movq    $(24 + 64), STATE_ROOT_HASH(%r14)   # the hash input: a ByteList of 64 bytes
    movq    $24, (STATE_ROOT_HASH + 8)(%r14)
    movq    $64, (STATE_ROOT_HASH + 16)(%r14)
    call    lantern_sr_zeros
    SR_FIELD_ROOTS none
    lea     STATE_ROOT_LEAVES(%r14), %rdi   # zeros to the width
    pxor    %xmm0, %xmm0
    mov     $SR_COUNT, %ecx
2:  cmp     $STATE_ROOT_WIDTH, %rcx
    jae     3f
    mov     %rcx, %rax
    shl     $5, %rax
    movdqu  %xmm0, (%rdi,%rax)
    movdqu  %xmm0, 16(%rdi,%rax)
    inc     %rcx
    jmp     2b
3:  mov     %r13, S8(%rsp)                  # the branch; for the finalized root, the epoch's leaf first
    mov     L(%rsp), %rax
    lea     22(%rax), %r15
    cmp     $LC_BRANCH_FINALIZED_ROOT, %rax
    jne     4f
    mov     $20, %r15d
    mov     (BeaconState_finalized_checkpoint + Checkpoint_epoch)(%rbx), %rax
    mov     %rax, (%r13)
    movq    $0, 8(%r13)
    movq    $0, 16(%r13)
    movq    $0, 24(%r13)
    addq    $32, S8(%rsp)
4:  mov     $STATE_ROOT_WIDTH, %ebp
5:  cmp     $1, %rbp                        # each level: the sibling, then the level above
    jbe     7f
    mov     %r15, %rax
    xor     $1, %rax
    shl     $5, %rax
    lea     STATE_ROOT_LEAVES(%r14,%rax), %rsi
    mov     S8(%rsp), %rdi
    COPY32  %rdi, %rsi
    addq    $32, S8(%rsp)
    shr     $1, %rbp
    movq    $0, S7(%rsp)
6:  mov     S7(%rsp), %rax
    lea     STATE_ROOT_LEAVES(%r14), %rdx
    mov     %rax, %rdi
    shl     $6, %rdi
    add     %rdx, %rdi
    lea     32(%rdi), %rsi
    shl     $5, %rax
    add     %rax, %rdx
    call    lantern_sr_hash
    incq    S7(%rsp)
    cmp     %rbp, S7(%rsp)
    jb      6b
    shr     $1, %r15
    jmp     5b
7:  mov     S9(%rsp), %rax
    mov     %rax, (%r12)
    xor     %eax, %eax
    LEAVE 16
98: mov     S9(%rsp), %rcx
    mov     %rcx, (%r12)
    LEAVE 16
99: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
97: mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 16
90: mov     S9(%rsp), %rax                  # ssz_build_proof of the state, into a Branch at the end of scratch
    mov     %rax, (%r12)
    sub     $(24 + 8 * 32), %rax
    jb      99b
    mov     %rax, (%r12)
    lea     (%r12,%rax), %r15
    movq    $(24 + 8 * 32), (%r15)
    movq    $24, 8(%r15)
    movq    $0, 16(%r15)
    ADDRESS %rdi, lantern_type_BeaconState
    mov     %rbx, %rsi
    lea     (L + 8)(%rsp), %rdx
    mov     %r12, %rcx
    mov     %r15, %r8
    CALL_GLOBAL ssz_build_proof
    mov     S9(%rsp), %rcx
    mov     %rcx, (%r12)
    test    %rax, %rax
    jnz     91f
    mov     16(%r15), %rdx
    shl     $5, %rdx
    lea     24(%r15), %rsi
    mov     %r13, %rdi
    call    lantern_copy
    xor     %eax, %eax
91: LEAVE 16
.endif
SPEC_END state_branch
