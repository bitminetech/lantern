/*
 * The hash tree root of a state from a StateCache, x86-64. Requirements: docs/reference/state.md.
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
 * L0: lays out the trees of the StateCache table for rdi validators, into cache rsi when it is
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
    call    lantern_sr_layout
    xor     %eax, %eax
    UNFRAME 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    UNFRAME 16
SPEC_END state_cache_init

.if FORK > FORK_PHASE0
/* L0: SHA-256 of the 32 bytes at rdi and the 32 bytes at rsi, to rdx, which may be rdi or rsi. r14 the area. */
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

/* L0: the zero hash of each depth 0 to 40 in the area at r14. rbx the next, rbp the hashes left. */
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
 * L0: the root of a field from tree rdi (a CacheTree): data rsi, count rdx elements, rcx the bytes
 * of an element of a basic type, or the descriptor of a container type (an address above 4095),
 * r8 the limit's depth + 256 for a list (mixed with the count), the root to r9. rax = 0, 1 when
 * the leaves pass the capacity, or a status of ssz_hash_tree_root. rbp the cache, r12 scratch with
 * its front's size set, r14 the area. rbx tree, r13 data then the level, r15 the leaves then the
 * nodes of the level, S7 a leaf then a word, S8 the level's nodes, S9 its dirty bits, S10 the old
 * count then the level's capacity. Locals: L count, L+8 element bytes, L+16 descriptor, L+24 depth,
 * L+32 list, L+40 out, L+48 the front's size, L+56 data bytes, L+64 the next level's nodes,
 * L+72 its dirty bits, L+80 a word, L+88 a parent, L+96 the leaves, L+104 a status.
 */
LOCAL_FUNCTION lantern_sr_tree
    ENTER 112
    mov     %rdi, %rbx
    mov     %rsi, %r13
    mov     %rdx, L(%rsp)
    xor     %eax, %eax
    cmp     $4096, %rcx
    jae     1f
    mov     %rcx, %rax
    xor     %ecx, %ecx
1:  mov     %rax, (L + 8)(%rsp)
    mov     %rcx, (L + 16)(%rsp)
    movzbl  %r8b, %eax
    mov     %rax, (L + 24)(%rsp)
    shr     $8, %r8
    mov     %r8, (L + 32)(%rsp)
    mov     %r9, (L + 40)(%rsp)
    mov     (%r12), %rax
    mov     %rax, (L + 48)(%rsp)
    mov     L(%rsp), %rax
    imulq   (L + 8)(%rsp), %rax
    mov     %rax, (L + 56)(%rsp)
    mov     L(%rsp), %r15                   # the leaves: elements, or chunks
    cmpq    $0, (L + 8)(%rsp)
    je      2f
    lea     31(%rax), %r15
    shr     $5, %r15
2:  mov     %r15, (L + 96)(%rsp)
    cmp     CacheTree_capacity(%rbx), %r15
    jbe     3f
    mov     $1, %eax
    LEAVE 112
3:  mov     CacheTree_count(%rbx), %rax
    mov     %rax, S10(%rsp)
    mov     CacheTree_nodes(%rbx), %rax
    add     %rbp, %rax
    mov     %rax, S8(%rsp)
    mov     CacheTree_dirty(%rbx), %rax
    add     %rbp, %rax
    mov     %rax, S9(%rsp)
    movq    $0, S7(%rsp)
4:  mov     S7(%rsp), %rcx
    cmp     %r15, %rcx
    jae     20f
    mov     %rcx, %rdi                      # the leaf
    shl     $5, %rdi
    add     S8(%rsp), %rdi
    cmpq    $0, (L + 8)(%rsp)
    je      10f
    mov     %rcx, %rsi                      # the chunk; the last one padded
    shl     $5, %rsi
    add     %r13, %rsi
    lea     1(%rcx), %rax
    cmp     %r15, %rax
    jne     6f
    mov     (L + 56)(%rsp), %rax
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
10: mov     CacheTree_copy(%rbx), %r8       # an element and its copy
    mov     %rcx, %rax
    imul    %r8, %rax
    lea     (%r13,%rax), %rsi
    mov     CacheTree_copies(%rbx), %rdx
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
    mov     (L + 48)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rdi, %rcx
    mov     (L + 16)(%rsp), %rdi
    mov     %r12, %rdx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jz      18f
    mov     %rax, (L + 104)(%rsp)           # a failure: the tree holds nothing
    movq    $0, CacheTree_count(%rbx)
    lea     63(%r15), %rcx
    shr     $6, %rcx
    mov     S9(%rsp), %rdi
    xor     %eax, %eax
    rep stosq
    mov     (L + 104)(%rsp), %rax
    LEAVE 112
18: mov     S7(%rsp), %rcx                  # the leaf is dirty
    mov     S9(%rsp), %rax
    mov     %rcx, %rdx
    shr     $6, %rdx
    mov     (%rax,%rdx,8), %r8
    bts     %rcx, %r8
    mov     %r8, (%rax,%rdx,8)
19: incq    S7(%rsp)
    jmp     4b
20: cmp     S10(%rsp), %r15                 # fewer leaves than the last root: the last one is dirty
    jae     21f
    test    %r15, %r15
    jz      21f
    lea     -1(%r15), %rcx
    mov     S9(%rsp), %rax
    mov     %rcx, %rdx
    shr     $6, %rdx
    mov     (%rax,%rdx,8), %r8
    bts     %rcx, %r8
    mov     %r8, (%rax,%rdx,8)
21: mov     CacheTree_capacity(%rbx), %rax
    mov     %rax, S10(%rsp)
    xor     %r13d, %r13d                    # level by level, the parents of dirty nodes
22: cmp     $1, %r15
    jbe     30f
    mov     S10(%rsp), %rax
    shl     $5, %rax
    add     S8(%rsp), %rax
    mov     %rax, (L + 64)(%rsp)
    mov     S10(%rsp), %rax
    add     $63, %rax
    shr     $6, %rax
    shl     $3, %rax
    add     S9(%rsp), %rax
    mov     %rax, (L + 72)(%rsp)
    movq    $0, S7(%rsp)
23: lea     63(%r15), %rax
    shr     $6, %rax
    cmp     %rax, S7(%rsp)
    jae     29f
    mov     S7(%rsp), %rcx
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
    mov     %rdx, (L + 80)(%rsp)
    mov     %rcx, (L + 88)(%rsp)
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
    add     (L + 64)(%rsp), %rdx
    call    lantern_sr_hash
    mov     (L + 88)(%rsp), %rcx            # the parent is dirty
    mov     (L + 72)(%rsp), %rax
    mov     %rcx, %rdx
    shr     $6, %rdx
    mov     (%rax,%rdx,8), %r8
    bts     %rcx, %r8
    mov     %r8, (%rax,%rdx,8)
    mov     (L + 80)(%rsp), %rdx
    jmp     24b
28: incq    S7(%rsp)
    jmp     23b
29: mov     (L + 64)(%rsp), %rax
    mov     %rax, S8(%rsp)
    mov     (L + 72)(%rsp), %rax
    mov     %rax, S9(%rsp)
    mov     S10(%rsp), %rax
    inc     %rax
    shr     $1, %rax
    mov     %rax, S10(%rsp)
    inc     %r15
    shr     $1, %r15
    inc     %r13
    jmp     22b
30: mov     S9(%rsp), %rax                  # the top's bit
    movq    $0, (%rax)
    mov     (L + 40)(%rsp), %rdi
    test    %r15, %r15
    jnz     31f
    mov     (L + 24)(%rsp), %rax            # no leaves: the zero hash of the limit's depth
    shl     $5, %rax
    add     %r14, %rax
    COPY32  %rdi, %rax
    jmp     33f
31: mov     S8(%rsp), %rax
    COPY32  %rdi, %rax
32: cmp     (L + 24)(%rsp), %r13            # up to the limit's depth
    jae     33f
    mov     (L + 40)(%rsp), %rdi
    mov     %r13, %rsi
    shl     $5, %rsi
    add     %r14, %rsi
    mov     %rdi, %rdx
    call    lantern_sr_hash
    inc     %r13
    jmp     32b
33: cmpq    $0, (L + 32)(%rsp)              # a list: mix_in_length
    je      34f
    lea     STATE_ROOT_CHUNK(%r14), %rsi
    mov     L(%rsp), %rax
    mov     %rax, (%rsi)
    movq    $0, 8(%rsi)
    movq    $0, 16(%rsi)
    movq    $0, 24(%rsi)
    mov     (L + 40)(%rsp), %rdi
    mov     %rdi, %rdx
    call    lantern_sr_hash
34: mov     (L + 96)(%rsp), %rax
    mov     %rax, CacheTree_count(%rbx)
    xor     %eax, %eax
    LEAVE 112
END_FUNCTION lantern_sr_tree
.endif

# The root of each field of the state into the leaves of the area, in field order: rbx state, rbp cache,
# r12 scratch, r14 the area, S10 the size of the front; r15, S7 and S8 are its own. To 90f for a tree past
# its capacity, 98f for a refusal of ssz.
.macro SR_FIELD_ROOTS
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
SPEC_FUNCTION state_root
    ENTER 16
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
    SR_FIELD_ROOTS
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
SPEC_END state_root

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
    SR_FIELD_ROOTS
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
