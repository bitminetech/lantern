/*
 * The eth1 follower of the node, x86-64: in the common object. Requirements: docs/reference/node.md
 * (the eth1 follower, Block production) and docs/reference/eth1.md.
 *
 * The step's helpers read the node from rbx, the store from rbp, the scratch from r14 and the
 * actions from r15.
 */

/*
 * With NODE_FLAG_ENGINE and NODE_FLAG_ETH1, after the head: when the store's epoch + 1 is above
 * eth1_check_epoch and the head's post-state is held, an ETH1_CHECK work of it. r12 the epoch + 1.
 */
LOCAL_FUNCTION lantern_node_eth1_check_due
    ENTER 0
    testq   $NODE_FLAG_ENGINE, Node_flags(%rbx)
    jz      9f
    testq   $NODE_FLAG_ETH1, Node_flags(%rbx)
    jz      9f
    mov     %rbp, %rdi
    call    lantern_node_store_slot
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    lea     1(%rax), %r12
    cmp     Node_eth1_check_epoch(%rbx), %r12
    jbe     9f
    lea     Node_head_root(%rbx), %rdi
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      9f
    mov     NodeBlock_state_id(%rdx), %rsi
    test    %rsi, %rsi
    jz      9f
    mov     %r12, Node_eth1_check_epoch(%rbx)
    mov     $NODE_WORK_ETH1_CHECK, %edi
    xor     %edx, %edx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    call    lantern_node_work
9:  LEAVE 0
END_FUNCTION lantern_node_eth1_check_due

/* rax = the start in seconds of the voting period of the store's slot (phase0 voting_period_start_time). Uses rcx, rdx. */
LOCAL_FUNCTION lantern_node_eth1_period
    FRAME 0
    mov     %rbp, %rdi
    call    lantern_node_store_slot
    xor     %edx, %edx
    mov     $(EPOCHS_PER_ETH1_VOTING_PERIOD * SLOTS_PER_EPOCH), %ecx
    div     %rcx
    imul    %rcx, %rax
    imul    (Node_config + CONFIG_SLOT_DURATION_MS)(%rbx), %rax
    add     Store_genesis_time_ms(%rbp), %rax
    xor     %edx, %edx
    mov     $1000, %ecx
    div     %rcx
    UNFRAME 0
END_FUNCTION lantern_node_eth1_period

/* rax = 2 * SECONDS_PER_ETH1_BLOCK * ETH1_FOLLOW_DISTANCE of the config. */
LOCAL_FUNCTION lantern_node_eth1_reach
    UNWIND_END_PROLOGUE
    mov     (Node_config + CONFIG_SECONDS_PER_ETH1_BLOCK)(%rbx), %rax
    imul    (Node_config + CONFIG_ETH1_FOLLOW_DISTANCE)(%rbx), %rax
    shl     $1, %rax
    ret
END_FUNCTION lantern_node_eth1_reach

/*
 * With eth1_state 1, the next eth1 call (node.md, the eth1 follower): the latest block when its
 * poll is due, else the logs up to the follow head, else a block of the window. rax = 1 when one
 * went, else 0. r12 the blocks, r13 the follow head, S7 the method, S8 a block's number or the
 * logs' first, S9 the logs' last, S10 the period start.
 */
LOCAL_FUNCTION lantern_node_eth1_next
    ENTER 0
    cmpq    $1, Node_eth1_state(%rbx)
    jne     8f
    movq    $ENGINE_METHOD_ETH_BLOCK, S7(%rsp)
    movq    $-1, S8(%rsp)
    movq    $0, S9(%rsp)
    mov     Node_eth1_head_ms(%rbx), %rax   # the latest: at first, then each SECONDS_PER_ETH1_BLOCK
    test    %rax, %rax
    jz      5f
    imul    $1000, (Node_config + CONFIG_SECONDS_PER_ETH1_BLOCK)(%rbx), %rcx
    add     %rcx, %rax
    cmp     %rax, Node_time_ms(%rbx)
    jae     5f
    mov     Node_eth1_head(%rbx), %r13      # the follow head
    sub     (Node_config + CONFIG_ETH1_FOLLOW_DISTANCE)(%rbx), %r13
    jb      8f
    mov     Node_eth1_logs_to(%rbx), %rax   # the logs up to it
    cmp     %r13, %rax
    ja      2f
    mov     %rax, S8(%rsp)
    add     $(NODE_ETH1_LOG_BLOCKS - 1), %rax
    cmp     %r13, %rax
    cmova   %r13, %rax
    mov     %rax, S9(%rsp)
    movq    $ENGINE_METHOD_ETH_LOGS, S7(%rsp)
    jmp     5f
2:  PART    %r12, %rcx, %rbx, Node_eth1_blocks  # the window: the follow head, then up to it, then down
    mov     %r13, S8(%rsp)
    test    %rcx, %rcx
    jz      5f
    lea     -1(%rcx), %rax
    imul    $Eth1Block__mem, %rax, %rax
    mov     Eth1Block_number(%r12,%rax), %rax
    lea     1(%rax), %rdx
    mov     %rdx, S8(%rsp)
    cmp     %r13, %rax
    jb      5f
    mov     Eth1Block_number(%r12), %rax
    test    %rax, %rax
    jz      8f
    dec     %rax
    mov     %rax, S8(%rsp)
    call    lantern_node_eth1_period
    mov     %rax, S10(%rsp)
    call    lantern_node_eth1_reach
    add     Eth1Block_timestamp(%r12), %rax
    cmp     S10(%rsp), %rax
    jb      8f
5:  mov     S7(%rsp), %rdi
    mov     S8(%rsp), %rsi
    mov     S9(%rsp), %rdx
    call    lantern_node_eth1_send
    LEAVE 0
8:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_node_eth1_next

/*
 * (method rdi, number or first rsi, last rdx): the eth1 call's request, with the id engine_id, in
 * lantern_http_post with the JWT of time_ms / 1000, in a NODE_ACT_ENGINE; engine_method the method
 * and eth1_call the block asked or the last. rax = 1 when it went, else 0. r12 the body, r13 the
 * token, S7 the method, S8 the number or first, S9 the last, S10 the host. Locals: L the scratch's
 * size, L+8 the id, L+16 and L+24 arguments.
 */
LOCAL_FUNCTION lantern_node_eth1_send
    ENTER 32
    mov     %rdi, S7(%rsp)
    mov     %rsi, S8(%rsp)
    mov     %rdx, S9(%rsp)
    mov     $(48 + 1024 + 7), %edi
    call    lantern_node_room
    test    %rax, %rax
    jz      7f
    mov     (%r14), %rax
    mov     %rax, L(%rsp)
    sub     $((24 + 512) + (24 + 256) + (24 + 64) + 1024), %rax
    jb      8f
    add     $1024, %rax                     # the JWT's scratch keeps 1024 bytes and more
    mov     %rax, (%r14)
    lea     (%r14,%rax), %r12               # the body, the token and the host, at the end of scratch
    movq    $(24 + 512), (%r12)
    movq    $24, 8(%r12)
    movq    $0, 16(%r12)
    lea     (24 + 512)(%r12), %r13
    movq    $(24 + 256), (%r13)
    movq    $24, 8(%r13)
    movq    $0, 16(%r13)
    lea     (24 + 256)(%r13), %rdi
    mov     %rdi, S10(%rsp)
    movq    $(24 + 64), (%rdi)
    movq    $24, 8(%rdi)
    mov     Node_engine_host_len(%rbx), %rdx
    mov     %rdx, 16(%rdi)
    add     $24, %rdi
    lea     Node_engine_host(%rbx), %rsi
    call    lantern_copy
    mov     Node_engine_id(%rbx), %rax
    mov     %rax, (L + 8)(%rsp)
    cmpq    $ENGINE_METHOD_ETH_LOGS, S7(%rsp)
    je      1f
    mov     S8(%rsp), %rax
    mov     %rax, (L + 16)(%rsp)
    lea     (L + 16)(%rsp), %rdi
    lea     (L + 8)(%rsp), %rsi
    mov     %r12, %rdx
    call    lantern_eth_get_block_by_number
    jmp     2f
1:  mov     S8(%rsp), %rax
    mov     %rax, (L + 16)(%rsp)
    mov     S9(%rsp), %rax
    mov     %rax, (L + 24)(%rsp)
    lea     (Node_config + CONFIG_DEPOSIT_CONTRACT_ADDRESS)(%rbx), %rdi
    lea     (L + 16)(%rsp), %rsi
    lea     (L + 24)(%rsp), %rdx
    lea     (L + 8)(%rsp), %rcx
    mov     %r12, %r8
    call    lantern_eth_get_deposit_logs
2:  test    %rax, %rax
    jnz     8f
    mov     Node_time_ms(%rbx), %rax        # the JWT at the time in seconds
    xor     %edx, %edx
    mov     $1000, %ecx
    div     %rcx
    mov     %rax, (L + 16)(%rsp)
    lea     Node_jwt_secret(%rbx), %rdi
    lea     (L + 16)(%rsp), %rsi
    mov     %r14, %rdx
    mov     %r13, %rcx
    call    lantern_jwt_token
    test    %rax, %rax
    jnz     8f
    mov     $NODE_ACT_ENGINE, %edi          # the request in the action
    mov     $(48 + 1024), %esi
    call    lantern_node_act
    movq    $0, 16(%rax)
    movq    $(24 + 1024), 24(%rax)
    movq    $24, 32(%rax)
    movq    $0, 40(%rax)
    lea     24(%rax), %rcx
    mov     S10(%rsp), %rdi
    mov     %r13, %rsi
    mov     %r12, %rdx
    call    lantern_http_post
    incq    Node_engine_id(%rbx)            # the call in flight
    mov     S7(%rsp), %rax
    mov     %rax, Node_engine_method(%rbx)
    mov     S8(%rsp), %rcx
    cmp     $ENGINE_METHOD_ETH_LOGS, %rax
    cmove   S9(%rsp), %rcx
    mov     %rcx, Node_eth1_call(%rbx)
    mov     L(%rsp), %rax
    mov     %rax, (%r14)
    mov     $1, %eax
    LEAVE 32
8:  mov     L(%rsp), %rax
    mov     %rax, (%r14)
7:  xor     %eax, %eax
    LEAVE 32
END_FUNCTION lantern_node_eth1_send

/*
 * The eth1 call in flight answered: the body rdi (a ByteList in scratch, which stays short) with
 * its EngineResponse rsi (node.md, the eth1 follower). A result the follower refuses, or a block
 * of another number, makes eth1_head_ms time_ms. r12 the deposits' list, r13 an entry, S7 the
 * entries left, S8 a leaf. Locals: L the result's ByteList (24), L+24 an Eth1Block (88), L+112 the
 * scratch's size.
 */
LOCAL_FUNCTION lantern_node_eth1_answer
    ENTER 128
    mov     8(%rdi), %rax                   # the result's ByteList: its bytes in the body
    add     %rdi, %rax
    add     EngineResponse_result_offset(%rsi), %rax
    mov     EngineResponse_result_length(%rsi), %rcx
    lea     L(%rsp), %rdx
    sub     %rdx, %rax
    mov     %rax, 8(%rdx)
    mov     %rcx, 16(%rdx)
    add     %rcx, %rax
    mov     %rax, (%rdx)
    cmpq    $ENGINE_METHOD_ETH_LOGS, Node_engine_method(%rbx)
    je      20f
    lea     L(%rsp), %rdi                   # a block
    lea     (L + 24)(%rsp), %rsi
    call    lantern_eth1_block
    test    %rax, %rax
    jnz     80f
    mov     Node_eth1_call(%rbx), %rcx
    mov     (L + 24 + Eth1Block_number)(%rsp), %rax
    cmp     $-1, %rcx
    jne     10f
    mov     %rax, Node_eth1_head(%rbx)      # the latest
    mov     Node_time_ms(%rbx), %rax
    mov     %rax, Node_eth1_head_ms(%rbx)
    LEAVE 128
10: cmp     %rcx, %rax
    jne     80f
    lea     (L + 24)(%rsp), %rdi
    call    lantern_node_eth1_block_add
    LEAVE 128
20: mov     (%r14), %rax                    # the logs: the deposits' list in scratch
    mov     %rax, (L + 112)(%rsp)
    sub     $(64 + 24), %rax
    jb      80f
    and     $-8, %rax
    movq    $64, (%r14)
    lea     64(%r14), %r12
    mov     %rax, (%r12)
    lea     L(%rsp), %rdi
    mov     %r12, %rsi
    call    lantern_eth1_deposit_logs
    test    %rax, %rax
    jnz     85f
    mov     16(%r12), %rax
    xor     %edx, %edx
    mov     $Eth1Deposit__mem, %ecx
    div     %rcx
    mov     %rax, S7(%rsp)
    mov     Node_eth1_leaves(%rbx), %rax    # room for them all
    sub     Node_eth1_deposits(%rbx), %rax
    xor     %edx, %edx
    div     %rcx
    mov     (Node_eth1_deposits + 8)(%rbx), %rdx
    add     S7(%rsp), %rdx
    cmp     %rax, %rdx
    ja      85f
    lea     24(%r12), %r13
30: cmpq    $0, S7(%rsp)                    # each deposit of the next index joins; one below it is skipped
    je      40f
    mov     (Node_eth1_deposits + 8)(%rbx), %rcx
    mov     Eth1Deposit_index(%r13), %rax
    cmp     %rcx, %rax
    jb      39f
    ja      85f
    lea     1(%rcx), %rax
    mov     %rax, (Node_eth1_deposits + 8)(%rbx)
    imul    $Eth1Deposit__mem, %rcx, %rdi
    add     Node_eth1_deposits(%rbx), %rdi
    add     %rbx, %rdi
    mov     %r13, %rsi
    mov     $Eth1Deposit__mem, %edx
    call    lantern_copy
    mov     (Node_eth1_leaves + 8)(%rbx), %rcx  # its leaf, then the tree
    lea     1(%rcx), %rax
    mov     %rax, (Node_eth1_leaves + 8)(%rbx)
    shl     $5, %rcx
    add     Node_eth1_leaves(%rbx), %rcx
    add     %rbx, %rcx
    mov     %rcx, S8(%rsp)
    lea     Eth1Deposit_data(%r13), %rdi
    mov     %rcx, %rsi
    call    lantern_deposit_leaf
    lea     Node_eth1_tree(%rbx), %rdi
    mov     S8(%rsp), %rsi
    call    lantern_deposit_tree_push
    test    %rax, %rax
    jnz     85f
    cmpq    $1, S7(%rsp)                    # after the block's last deposit: its count
    je      31f
    mov     (Eth1Deposit__mem + Eth1Deposit_block_number)(%r13), %rax
    cmp     Eth1Deposit_block_number(%r13), %rax
    je      39f
31: mov     (Node_eth1_counts + 8)(%rbx), %rcx
    lea     1(%rcx), %rax
    mov     %rax, (Node_eth1_counts + 8)(%rbx)
    imul    $Eth1Count__mem, %rcx, %rcx
    add     Node_eth1_counts(%rbx), %rcx
    add     %rbx, %rcx
    mov     Eth1Deposit_block_number(%r13), %rax
    mov     %rax, Eth1Count_number(%rcx)
    mov     (Node_eth1_tree + DepositTree_count)(%rbx), %rax
    mov     %rax, Eth1Count_count(%rcx)
    lea     Node_eth1_tree(%rbx), %rdi
    lea     Eth1Count_root(%rcx), %rsi
    call    lantern_deposit_tree_root
39: add     $Eth1Deposit__mem, %r13
    decq    S7(%rsp)
    jmp     30b
40: mov     (L + 112)(%rsp), %rax           # the range is in
    mov     %rax, (%r14)
    mov     Node_eth1_call(%rbx), %rax
    inc     %rax
    mov     %rax, Node_eth1_logs_to(%rbx)
    LEAVE 128
85: mov     (L + 112)(%rsp), %rax
    mov     %rax, (%r14)
80: mov     Node_time_ms(%rbx), %rax        # a failed call: the next head poll
    mov     %rax, Node_eth1_head_ms(%rbx)
    LEAVE 128
END_FUNCTION lantern_node_eth1_answer

/*
 * The Eth1Block rdi of an answer, its number, hash and timestamp set, joins eth1_blocks after the
 * highest or before the lowest (node.md, the eth1 follower), its count and root those of the last
 * eth1_counts entry at or below its number. r12 the block, r13 its number, S7 the entries, S8 their
 * count, S9 the capacity, S10 an index. Locals: L a DepositTree count of 0, L+8 the period start,
 * L+16 the reach.
 */
LOCAL_FUNCTION lantern_node_eth1_block_add
    ENTER 32
    mov     %rdi, %r12
    mov     Eth1Block_number(%r12), %r13
    PART    %rsi, %rcx, %rbx, Node_eth1_counts  # its count and root
1:  test    %rcx, %rcx
    jz      2f
    dec     %rcx
    imul    $Eth1Count__mem, %rcx, %rax
    cmp     %r13, Eth1Count_number(%rsi,%rax)
    ja      1b
    lea     (%rsi,%rax), %rax
    mov     Eth1Count_count(%rax), %rcx
    mov     %rcx, Eth1Block_deposit_count(%r12)
    lea     Eth1Count_root(%rax), %rsi
    lea     Eth1Block_deposit_root(%r12), %rdi
    COPY32  %rdi, %rsi
    jmp     3f
2:  movq    $0, Eth1Block_deposit_count(%r12)   # none: the root of no deposits
    movq    $0, L(%rsp)
    lea     L(%rsp), %rdi
    lea     Eth1Block_deposit_root(%r12), %rsi
    call    lantern_deposit_tree_root
3:  PART    %rax, %rcx, %rbx, Node_eth1_blocks
    mov     %rax, S7(%rsp)
    mov     %rcx, S8(%rsp)
    mov     Node_eth1_deposits(%rbx), %rax
    sub     Node_eth1_blocks(%rbx), %rax
    xor     %edx, %edx
    mov     $Eth1Block__mem, %ecx
    div     %rcx
    mov     %rax, S9(%rsp)
    test    %rax, %rax
    jz      9f
    mov     S8(%rsp), %rcx
    test    %rcx, %rcx
    jz      5f
    dec     %rcx                            # after the highest
    imul    $Eth1Block__mem, %rcx, %rcx
    add     S7(%rsp), %rcx
    mov     Eth1Block_number(%rcx), %rax
    inc     %rax
    cmp     %rax, %r13
    je      5f
    mov     S7(%rsp), %rcx                  # before the lowest, with room
    mov     Eth1Block_number(%rcx), %rax
    dec     %rax
    cmp     %rax, %r13
    jne     9f
    mov     S8(%rsp), %rax
    cmp     S9(%rsp), %rax
    jae     9f
    mov     %rax, S10(%rsp)                 # each entry one up, from the highest
4:  cmpq    $0, S10(%rsp)
    je      41f
    decq    S10(%rsp)
    imul    $Eth1Block__mem, S10(%rsp), %rsi
    add     S7(%rsp), %rsi
    lea     Eth1Block__mem(%rsi), %rdi
    mov     $Eth1Block__mem, %edx
    call    lantern_copy
    jmp     4b
41: incq    (Node_eth1_blocks + 8)(%rbx)
    mov     S7(%rsp), %rdi
    mov     %r12, %rsi
    mov     $Eth1Block__mem, %edx
    call    lantern_copy
    jmp     6f
5:  mov     S8(%rsp), %rax                  # after the highest; no room: the lowest goes first
    cmp     S9(%rsp), %rax
    jb      51f
    call    lantern_node_eth1_block_drop
51: PART    %rdi, %rcx, %rbx, Node_eth1_blocks
    imul    $Eth1Block__mem, %rcx, %rax
    add     %rax, %rdi
    incq    (Node_eth1_blocks + 8)(%rbx)
    mov     %r12, %rsi
    mov     $Eth1Block__mem, %edx
    call    lantern_copy
6:  call    lantern_node_eth1_period                # while the second entry is before the period's reach, the lowest goes
    mov     %rax, (L + 8)(%rsp)
    call    lantern_node_eth1_reach
    mov     %rax, (L + 16)(%rsp)
7:  PART    %rax, %rcx, %rbx, Node_eth1_blocks
    cmp     $1, %rcx
    jbe     9f
    mov     (Eth1Block__mem + Eth1Block_timestamp)(%rax), %rax
    add     (L + 16)(%rsp), %rax
    cmp     (L + 8)(%rsp), %rax
    jae     9f
    call    lantern_node_eth1_block_drop
    jmp     7b
9:  LEAVE 32
END_FUNCTION lantern_node_eth1_block_add

/* The lowest eth1_blocks entry goes: each other one down. r12 the entries, r13 the index, S7 the count. */
LOCAL_FUNCTION lantern_node_eth1_block_drop
    ENTER 0
    PART    %r12, %rax, %rbx, Node_eth1_blocks
    mov     %rax, S7(%rsp)
    test    %rax, %rax
    jz      9f
    mov     $1, %r13d
1:  cmp     S7(%rsp), %r13
    jae     2f
    imul    $Eth1Block__mem, %r13, %rsi
    add     %r12, %rsi
    lea     -Eth1Block__mem(%rsi), %rdi
    mov     $Eth1Block__mem, %edx
    call    lantern_copy
    inc     %r13
    jmp     1b
2:  decq    (Node_eth1_blocks + 8)(%rbx)
9:  LEAVE 0
END_FUNCTION lantern_node_eth1_block_drop

/*
 * rax = the bytes of the follower's Eth1Snapshot (node.md): with eth1_state 1 its blocks, the
 * deposits from eth1_deposit_index, at most MAX_DEPOSITS, and every leaf; else none. rsi the
 * blocks, rdx the deposits, rcx the leaves, r8 the first deposit.
 */
LOCAL_FUNCTION lantern_node_eth1_snapshot_size
    UNWIND_END_PROLOGUE
    xor     %esi, %esi
    xor     %edx, %edx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    cmpq    $1, Node_eth1_state(%rbx)
    jne     1f
    mov     (Node_eth1_blocks + 8)(%rbx), %rsi
    mov     Node_eth1_deposit_index(%rbx), %r8
    mov     (Node_eth1_deposits + 8)(%rbx), %rdx
    sub     %r8, %rdx
    jae     2f
    xor     %edx, %edx
2:  cmp     $MAX_DEPOSITS, %rdx
    jbe     3f
    mov     $MAX_DEPOSITS, %edx
3:  mov     (Node_eth1_leaves + 8)(%rbx), %rcx
1:  imul    $Eth1Block__mem, %rsi, %rax
    add     $Eth1Snapshot__fixed, %rax
    imul    $Eth1Deposit__mem, %rdx, %r9
    add     %r9, %rax
    mov     %rcx, %r9
    shl     $5, %r9
    add     %r9, %rax
    ret
END_FUNCTION lantern_node_eth1_snapshot_size

/*
 * rax = the id of a new BYTES_PUT of the follower's Eth1Snapshot (node.md, NODE_PRODUCE_ETH1). r12
 * the snapshot, r13 the id, S7 the blocks, S8 the deposits, S9 the leaves, S10 the first deposit.
 */
LOCAL_FUNCTION lantern_node_eth1_snapshot
    ENTER 0
    call    lantern_node_new_id
    mov     %rax, %r13
    call    lantern_node_eth1_snapshot_size
    mov     %rsi, S7(%rsp)
    mov     %rdx, S8(%rsp)
    mov     %rcx, S9(%rsp)
    mov     %r8, S10(%rsp)
    mov     %rax, %r12
    lea     (48 + 7)(%rax), %rsi
    and     $-8, %rsi
    mov     $NODE_ACT_BYTES_PUT, %edi
    call    lantern_node_act
    mov     %r13, 16(%rax)
    mov     (%rax), %rcx
    sub     $24, %rcx
    mov     %rcx, 24(%rax)
    movq    $24, 32(%rax)
    mov     %r12, 40(%rax)
    lea     48(%rax), %r12
    mov     S7(%rsp), %rax
    mov     %rax, Eth1Snapshot_blocks(%r12)
    mov     S8(%rsp), %rax
    mov     %rax, Eth1Snapshot_deposits(%r12)
    mov     S9(%rsp), %rax
    mov     %rax, Eth1Snapshot_leaves(%r12)
    lea     Eth1Snapshot__fixed(%r12), %rdi # the blocks
    mov     Node_eth1_blocks(%rbx), %rsi
    add     %rbx, %rsi
    imul    $Eth1Block__mem, S7(%rsp), %rdx
    lea     (%rdi,%rdx), %r12
    call    lantern_copy
    mov     %r12, %rdi                      # the deposits
    imul    $Eth1Deposit__mem, S10(%rsp), %rsi
    add     Node_eth1_deposits(%rbx), %rsi
    add     %rbx, %rsi
    imul    $Eth1Deposit__mem, S8(%rsp), %rdx
    lea     (%rdi,%rdx), %r12
    call    lantern_copy
    mov     %r12, %rdi                      # the leaves
    mov     Node_eth1_leaves(%rbx), %rsi
    add     %rbx, %rsi
    mov     S9(%rsp), %rdx
    shl     $5, %rdx
    call    lantern_copy
    mov     %r13, %rax
    LEAVE 0
END_FUNCTION lantern_node_eth1_snapshot
