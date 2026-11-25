/*
 * The eth1 follower of the node, ARM64: in the common object. Requirements: docs/reference/node.md
 * (the eth1 follower, Block production) and docs/reference/eth1.md.
 *
 * The step's helpers read the node from x19, the store from x20, the scratch from x23 and the
 * actions from x24.
 */

/*
 * With NODE_FLAG_ENGINE and NODE_FLAG_ETH1, after the head: when the store's epoch + 1 is above eth1_check_epoch
 * and the head's post-state is held, an ETH1_CHECK work of it. x21 the epoch + 1.
 */
LOCAL_FUNCTION lantern_node_eth1_check_due
    ENTER 0
    ldr     x9, [x19, #Node_flags]
    tst     x9, #NODE_FLAG_ENGINE
    b.eq    9f
    tst     x9, #NODE_FLAG_ETH1
    b.eq    9f
    mov     x0, x20
    bl      lantern_node_store_slot
    mov     x9, #SLOTS_PER_EPOCH
    udiv    x21, x0, x9
    add     x21, x21, #1
    LDQ     x9, x19, Node_eth1_check_epoch
    cmp     x21, x9
    b.ls    9f
    add     x0, x19, #Node_head_root
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    9f
    ldr     x1, [x1, #NodeBlock_state_id]
    cbz     x1, 9f
    STQ     x21, x19, Node_eth1_check_epoch
    mov     x0, #NODE_WORK_ETH1_CHECK
    mov     x2, #0
    mov     x3, #0
    mov     x4, #0
    mov     x5, #0
    bl      lantern_node_work
9:  LEAVE 0
END_FUNCTION lantern_node_eth1_check_due

/* x0 = the start in seconds of the voting period of the store's slot (phase0 voting_period_start_time). Uses x9-x11. */
LOCAL_FUNCTION lantern_node_eth1_period
    FRAME 0
    mov     x0, x20
    bl      lantern_node_store_slot
    MOVQ    x9, EPOCHS_PER_ETH1_VOTING_PERIOD * SLOTS_PER_EPOCH
    udiv    x10, x0, x9
    mul     x10, x10, x9
    LDQ     x11, x19, Node_config + CONFIG_SLOT_DURATION_MS
    mul     x10, x10, x11
    ldr     x11, [x20, #Store_genesis_time_ms]
    add     x10, x10, x11
    mov     x11, #1000
    udiv    x0, x10, x11
    UNFRAME 0
END_FUNCTION lantern_node_eth1_period

/* x0 = 2 * SECONDS_PER_ETH1_BLOCK * ETH1_FOLLOW_DISTANCE of the config. Uses x9, x10. */
LOCAL_FUNCTION lantern_node_eth1_reach
    UNWIND_END_PROLOGUE
    LDQ     x9, x19, Node_config + CONFIG_SECONDS_PER_ETH1_BLOCK
    LDQ     x10, x19, Node_config + CONFIG_ETH1_FOLLOW_DISTANCE
    mul     x0, x9, x10
    lsl     x0, x0, #1
    ret
END_FUNCTION lantern_node_eth1_reach

/*
 * With eth1_state 1, the next eth1 call (node.md, the eth1 follower): the latest block when its
 * poll is due, else the logs up to the follow head, else a block of the window. x0 = 1 when one
 * went, else 0. x21 the blocks, x22 their count, x25 the follow head, x26 a block's number or the
 * logs' first, x27 the logs' last, x28 the method.
 */
LOCAL_FUNCTION lantern_node_eth1_next
    ENTER 0
    LDQ     x9, x19, Node_eth1_state
    cmp     x9, #1
    b.ne    8f
    mov     x28, #ENGINE_METHOD_ETH_BLOCK
    mov     x26, #-1
    mov     x27, #0
    LDQ     x10, x19, Node_eth1_head_ms     /* the latest: at first, then each SECONDS_PER_ETH1_BLOCK */
    cbz     x10, 5f
    LDQ     x11, x19, Node_config + CONFIG_SECONDS_PER_ETH1_BLOCK
    mov     x12, #1000
    madd    x10, x11, x12, x10
    ldr     x11, [x19, #Node_time_ms]
    cmp     x11, x10
    b.hs    5f
    LDQ     x25, x19, Node_eth1_head        /* the follow head */
    LDQ     x9, x19, Node_config + CONFIG_ETH1_FOLLOW_DISTANCE
    subs    x25, x25, x9
    b.lo    8f
    LDQ     x26, x19, Node_eth1_logs_to     /* the logs up to it */
    cmp     x26, x25
    b.hi    2f
    MOVQ    x9, NODE_ETH1_LOG_BLOCKS - 1
    add     x27, x26, x9
    cmp     x27, x25
    csel    x27, x25, x27, hi
    mov     x28, #ENGINE_METHOD_ETH_LOGS
    b       5f
2:  PART    x21, x22, x19, Node_eth1_blocks /* the window: the follow head, then up to it, then down */
    mov     x26, x25
    cbz     x22, 5f
    sub     x9, x22, #1
    mov     x10, #Eth1Block__mem
    madd    x9, x9, x10, x21
    ldr     x26, [x9, #Eth1Block_number]
    cmp     x26, x25
    add     x26, x26, #1
    b.lo    5f
    ldr     x26, [x21, #Eth1Block_number]
    cbz     x26, 8f
    bl      lantern_node_eth1_period
    mov     x27, x0
    bl      lantern_node_eth1_reach
    ldr     x9, [x21, #Eth1Block_timestamp]
    add     x9, x9, x0
    cmp     x9, x27
    b.lo    8f
    sub     x26, x26, #1
5:  mov     x0, x28
    mov     x1, x26
    mov     x2, x27
    bl      lantern_node_eth1_send
    LEAVE 0
8:  mov     x0, #0
    LEAVE 0
END_FUNCTION lantern_node_eth1_next

/*
 * (method x0, number or first x1, last x2): the eth1 call's request, with the id engine_id, in
 * lantern_http_post with the JWT of time_ms / 1000, in a NODE_ACT_ENGINE; engine_method the
 * method and eth1_call the block asked or the last. x0 = 1 when it went, else 0. x21 the method,
 * x22 the number or first, x25 the last, x26 the body, x27 the token, x28 the host. Locals: L the
 * scratch's size, L+8 the id, L+16 and L+24 arguments.
 */
LOCAL_FUNCTION lantern_node_eth1_send
    ENTER 32
    mov     x21, x0
    mov     x22, x1
    mov     x25, x2
    mov     x0, #(48 + 1024 + 7)
    bl      lantern_node_room
    cbz     x0, 7f
    ldr     x9, [x23]
    str     x9, [sp, #L]
    MOVQ    x10, (24 + 512) + (24 + 256) + (24 + 64) + 1024
    subs    x9, x9, x10
    b.lo    8f
    add     x9, x9, #1024                   /* the JWT's scratch keeps 1024 bytes and more */
    str     x9, [x23]
    add     x26, x23, x9                    /* the body, the token and the host, at the end of scratch */
    mov     x10, #(24 + 512)
    mov     x11, #24
    stp     x10, x11, [x26]
    str     xzr, [x26, #16]
    add     x27, x26, #(24 + 512)
    mov     x10, #(24 + 256)
    stp     x10, x11, [x27]
    str     xzr, [x27, #16]
    add     x28, x27, #(24 + 256)
    mov     x10, #(24 + 64)
    stp     x10, x11, [x28]
    ldr     x2, [x19, #Node_engine_host_len]
    str     x2, [x28, #16]
    add     x0, x28, #24
    add     x1, x19, #Node_engine_host
    bl      lantern_copy
    ldr     x9, [x19, #Node_engine_id]
    str     x9, [sp, #(L + 8)]
    cmp     x21, #ENGINE_METHOD_ETH_LOGS
    b.eq    1f
    str     x22, [sp, #(L + 16)]
    add     x0, sp, #(L + 16)
    add     x1, sp, #(L + 8)
    mov     x2, x26
    bl      lantern_eth_get_block_by_number
    b       2f
1:  stp     x22, x25, [sp, #(L + 16)]
    ADDQ    x0, x19, Node_config + CONFIG_DEPOSIT_CONTRACT_ADDRESS
    add     x1, sp, #(L + 16)
    add     x2, sp, #(L + 24)
    add     x3, sp, #(L + 8)
    mov     x4, x26
    bl      lantern_eth_get_deposit_logs
2:  cbnz    x0, 8f
    ldr     x9, [x19, #Node_time_ms]        /* the JWT at the time in seconds */
    mov     x10, #1000
    udiv    x9, x9, x10
    str     x9, [sp, #(L + 16)]
    add     x0, x19, #Node_jwt_secret
    add     x1, sp, #(L + 16)
    mov     x2, x23
    mov     x3, x27
    bl      lantern_jwt_token
    cbnz    x0, 8f
    mov     x0, #NODE_ACT_ENGINE            /* the request in the action */
    mov     x1, #(48 + 1024)
    bl      lantern_node_act
    str     xzr, [x0, #16]
    mov     x9, #(24 + 1024)
    mov     x10, #24
    stp     x9, x10, [x0, #24]
    str     xzr, [x0, #40]
    add     x3, x0, #24
    mov     x0, x28
    mov     x1, x27
    mov     x2, x26
    bl      lantern_http_post
    ldr     x9, [x19, #Node_engine_id]      /* the call in flight */
    add     x9, x9, #1
    str     x9, [x19, #Node_engine_id]
    str     x21, [x19, #Node_engine_method]
    cmp     x21, #ENGINE_METHOD_ETH_LOGS
    csel    x9, x25, x22, eq
    STQ     x9, x19, Node_eth1_call
    ldr     x9, [sp, #L]
    str     x9, [x23]
    mov     x0, #1
    LEAVE 32
8:  ldr     x9, [sp, #L]
    str     x9, [x23]
7:  mov     x0, #0
    LEAVE 32
END_FUNCTION lantern_node_eth1_send

/*
 * The eth1 call in flight answered: the body x0 (a ByteList in scratch, which stays short)
 * with its EngineResponse x1 (node.md, the eth1 follower). A result the follower refuses, or a
 * block of another number, makes eth1_head_ms time_ms. x21 the deposits' list, x22 its entries,
 * x25 an entry, x26 the entries left, x27 a part's base, x28 a count's entry. Locals: L the
 * result's ByteList (24), L+24 an Eth1Block (88), L+112 the scratch's size.
 */
LOCAL_FUNCTION lantern_node_eth1_answer
    ENTER 128
    ldr     x9, [x0, #8]                    /* the result's ByteList: its bytes in the body */
    add     x9, x0, x9
    ldr     x10, [x1, #EngineResponse_result_offset]
    add     x9, x9, x10
    ldr     x11, [x1, #EngineResponse_result_length]
    add     x12, sp, #L
    sub     x13, x9, x12
    add     x10, x13, x11
    stp     x10, x13, [x12]
    str     x11, [x12, #16]
    ldr     x9, [x19, #Node_engine_method]
    cmp     x9, #ENGINE_METHOD_ETH_LOGS
    b.eq    20f
    add     x0, sp, #L                      /* a block */
    add     x1, sp, #(L + 24)
    bl      lantern_eth1_block
    cbnz    x0, 80f
    LDQ     x9, x19, Node_eth1_call
    ldr     x10, [sp, #(L + 24 + Eth1Block_number)]
    cmn     x9, #1
    b.ne    10f
    STQ     x10, x19, Node_eth1_head        /* the latest */
    ldr     x9, [x19, #Node_time_ms]
    STQ     x9, x19, Node_eth1_head_ms
    LEAVE 128
10: cmp     x10, x9
    b.ne    80f
    add     x0, sp, #(L + 24)
    bl      lantern_node_eth1_block_add
    LEAVE 128
20: ldr     x9, [x23]                       /* the logs: the deposits' list in scratch */
    str     x9, [sp, #(L + 112)]
    subs    x10, x9, #(64 + 24)
    b.lo    80f
    and     x10, x10, #~7
    mov     x11, #64
    str     x11, [x23]
    add     x21, x23, #64
    str     x10, [x21]
    add     x0, sp, #L
    mov     x1, x21
    bl      lantern_eth1_deposit_logs
    cbnz    x0, 85f
    ldr     x9, [x21, #16]
    mov     x10, #Eth1Deposit__mem
    udiv    x22, x9, x10
    ldr     x9, [x19, #Node_eth1_deposits]  /* room for them all */
    ldr     x10, [x19, #Node_eth1_leaves]
    sub     x10, x10, x9
    mov     x11, #Eth1Deposit__mem
    udiv    x10, x10, x11
    ldr     x9, [x19, #(Node_eth1_deposits + 8)]
    add     x9, x9, x22
    cmp     x9, x10
    b.hi    85f
    add     x25, x21, #24
    mov     x26, x22
30: cbz     x26, 40f                        /* each deposit of the next index joins; one below it is skipped */
    PART    x27, x9, x19, Node_eth1_deposits
    ldr     x10, [x25, #Eth1Deposit_index]
    cmp     x10, x9
    b.lo    39f
    b.hi    85f
    mov     x11, #Eth1Deposit__mem
    madd    x0, x9, x11, x27
    add     x9, x9, #1
    str     x9, [x19, #(Node_eth1_deposits + 8)]
    mov     x1, x25
    mov     x2, #Eth1Deposit__mem
    bl      lantern_copy
    PART    x27, x9, x19, Node_eth1_leaves  /* its leaf, then the tree */
    add     x10, x9, #1
    str     x10, [x19, #(Node_eth1_leaves + 8)]
    add     x28, x27, x9, lsl #5
    add     x0, x25, #Eth1Deposit_data
    mov     x1, x28
    bl      lantern_deposit_leaf
    ADDQ    x0, x19, Node_eth1_tree
    mov     x1, x28
    bl      lantern_deposit_tree_push
    cbnz    x0, 85f
    cmp     x26, #1                         /* after the block's last deposit: its count */
    b.eq    31f
    ldr     x9, [x25, #(Eth1Deposit__mem + Eth1Deposit_block_number)]
    ldr     x10, [x25, #Eth1Deposit_block_number]
    cmp     x9, x10
    b.eq    39f
31: PART    x27, x9, x19, Node_eth1_counts
    add     x10, x9, #1
    str     x10, [x19, #(Node_eth1_counts + 8)]
    mov     x11, #Eth1Count__mem
    madd    x28, x9, x11, x27
    ldr     x9, [x25, #Eth1Deposit_block_number]
    str     x9, [x28, #Eth1Count_number]
    ADDQ    x0, x19, Node_eth1_tree
    ldr     x9, [x0, #DepositTree_count]
    str     x9, [x28, #Eth1Count_count]
    add     x1, x28, #Eth1Count_root
    bl      lantern_deposit_tree_root
39: add     x25, x25, #Eth1Deposit__mem
    sub     x26, x26, #1
    b       30b
40: ldr     x9, [sp, #(L + 112)]            /* the range is in */
    str     x9, [x23]
    LDQ     x9, x19, Node_eth1_call
    add     x9, x9, #1
    STQ     x9, x19, Node_eth1_logs_to
    LEAVE 128
85: ldr     x9, [sp, #(L + 112)]
    str     x9, [x23]
80: ldr     x9, [x19, #Node_time_ms]        /* a failed call: the next head poll */
    STQ     x9, x19, Node_eth1_head_ms
    LEAVE 128
END_FUNCTION lantern_node_eth1_answer

/*
 * The Eth1Block x0 of an answer, its number, hash and timestamp set, joins eth1_blocks after the
 * highest or before the lowest (node.md, the eth1 follower), its count and root those of the last
 * eth1_counts entry at or below its number. x21 the block, x22 its number, x25 the entries, x26
 * their count, x27 the capacity. Locals: L a DepositTree count of 0.
 */
LOCAL_FUNCTION lantern_node_eth1_block_add
    ENTER 16
    mov     x21, x0
    ldr     x22, [x21, #Eth1Block_number]
    PART    x9, x10, x19, Node_eth1_counts  /* its count and root */
1:  cbz     x10, 2f
    sub     x10, x10, #1
    mov     x11, #Eth1Count__mem
    madd    x12, x10, x11, x9
    ldr     x13, [x12, #Eth1Count_number]
    cmp     x13, x22
    b.hi    1b
    ldr     x13, [x12, #Eth1Count_count]
    str     x13, [x21, #Eth1Block_deposit_count]
    add     x0, x21, #Eth1Block_deposit_root
    add     x1, x12, #Eth1Count_root
    COPY32  x0, x1
    b       3f
2:  str     xzr, [x21, #Eth1Block_deposit_count]   /* none: the root of no deposits */
    str     xzr, [sp, #L]
    add     x0, sp, #L
    add     x1, x21, #Eth1Block_deposit_root
    bl      lantern_deposit_tree_root
3:  PART    x25, x26, x19, Node_eth1_blocks
    ldr     x9, [x19, #Node_eth1_deposits]
    ldr     x10, [x19, #Node_eth1_blocks]
    sub     x9, x9, x10
    mov     x10, #Eth1Block__mem
    udiv    x27, x9, x10
    cbz     x27, 9f
    cbz     x26, 5f
    sub     x9, x26, #1                     /* after the highest */
    mov     x10, #Eth1Block__mem
    madd    x9, x9, x10, x25
    ldr     x9, [x9, #Eth1Block_number]
    add     x9, x9, #1
    cmp     x22, x9
    b.eq    5f
    ldr     x9, [x25, #Eth1Block_number]    /* before the lowest, with room */
    sub     x9, x9, #1
    cmp     x22, x9
    b.ne    9f
    cmp     x26, x27
    b.hs    9f
    mov     x28, x26                        /* each entry one up, from the highest */
4:  cbz     x28, 41f
    sub     x28, x28, #1
    mov     x10, #Eth1Block__mem
    madd    x1, x28, x10, x25
    add     x0, x1, #Eth1Block__mem
    mov     x2, #Eth1Block__mem
    bl      lantern_copy
    b       4b
41: add     x26, x26, #1
    str     x26, [x19, #(Node_eth1_blocks + 8)]
    mov     x0, x25
    mov     x1, x21
    mov     x2, #Eth1Block__mem
    bl      lantern_copy
    b       6f
5:  cmp     x26, x27                        /* after the highest; no room: the lowest goes first */
    b.lo    51f
    bl      lantern_node_eth1_block_drop
    PART    x25, x26, x19, Node_eth1_blocks
51: mov     x10, #Eth1Block__mem
    madd    x0, x26, x10, x25
    add     x26, x26, #1
    str     x26, [x19, #(Node_eth1_blocks + 8)]
    mov     x1, x21
    mov     x2, #Eth1Block__mem
    bl      lantern_copy
6:  bl      lantern_node_eth1_period                /* while the second entry is before the period's reach, the lowest goes */
    mov     x21, x0
    bl      lantern_node_eth1_reach
    mov     x22, x0
7:  PART    x25, x26, x19, Node_eth1_blocks
    cmp     x26, #1
    b.ls    9f
    ldr     x9, [x25, #(Eth1Block__mem + Eth1Block_timestamp)]
    add     x9, x9, x22
    cmp     x9, x21
    b.hs    9f
    bl      lantern_node_eth1_block_drop
    b       7b
9:  LEAVE 16
END_FUNCTION lantern_node_eth1_block_add

/* The lowest eth1_blocks entry goes: each other one down. x21 the entries, x22 the count, x25 the index. */
LOCAL_FUNCTION lantern_node_eth1_block_drop
    ENTER 0
    PART    x21, x22, x19, Node_eth1_blocks
    cbz     x22, 9f
    mov     x25, #1
1:  cmp     x25, x22
    b.hs    2f
    mov     x10, #Eth1Block__mem
    madd    x1, x25, x10, x21
    sub     x0, x1, #Eth1Block__mem
    mov     x2, #Eth1Block__mem
    bl      lantern_copy
    add     x25, x25, #1
    b       1b
2:  sub     x22, x22, #1
    str     x22, [x19, #(Node_eth1_blocks + 8)]
9:  LEAVE 0
END_FUNCTION lantern_node_eth1_block_drop

/*
 * x0 = the bytes of the follower's Eth1Snapshot (node.md): with eth1_state 1 its blocks, the
 * deposits from eth1_deposit_index, at most MAX_DEPOSITS, and every leaf; else none. x1 the
 * blocks, x2 the deposits, x3 the leaves, x4 the first deposit. Uses x9-x12.
 */
LOCAL_FUNCTION lantern_node_eth1_snapshot_size
    UNWIND_END_PROLOGUE
    mov     x1, #0
    mov     x2, #0
    mov     x3, #0
    mov     x4, #0
    LDQ     x9, x19, Node_eth1_state
    cmp     x9, #1
    b.ne    1f
    ldr     x1, [x19, #(Node_eth1_blocks + 8)]
    ldr     x10, [x19, #(Node_eth1_deposits + 8)]
    LDQ     x4, x19, Node_eth1_deposit_index
    subs    x2, x10, x4
    csel    x2, xzr, x2, lo
    mov     x9, #MAX_DEPOSITS
    cmp     x2, x9
    csel    x2, x9, x2, hi
    ldr     x3, [x19, #(Node_eth1_leaves + 8)]
1:  mov     x0, #Eth1Snapshot__fixed
    mov     x9, #Eth1Block__mem
    madd    x0, x1, x9, x0
    mov     x9, #Eth1Deposit__mem
    madd    x0, x2, x9, x0
    add     x0, x0, x3, lsl #5
    ret
END_FUNCTION lantern_node_eth1_snapshot_size

/*
 * x0 = the id of a new BYTES_PUT of the follower's Eth1Snapshot (node.md, NODE_PRODUCE_ETH1).
 * x21 the blocks, x22 the deposits, x25 the leaves, x26 the first deposit, x27 the snapshot, x28
 * the id.
 */
LOCAL_FUNCTION lantern_node_eth1_snapshot
    ENTER 0
    bl      lantern_node_new_id
    mov     x28, x0
    bl      lantern_node_eth1_snapshot_size
    mov     x21, x1
    mov     x22, x2
    mov     x25, x3
    mov     x26, x4
    mov     x27, x0
    add     x1, x0, #(48 + 7)
    and     x1, x1, #~7
    mov     x0, #NODE_ACT_BYTES_PUT
    bl      lantern_node_act
    str     x28, [x0, #16]
    ldr     x9, [x0]
    sub     x9, x9, #24
    mov     x10, #24
    stp     x9, x10, [x0, #24]
    str     x27, [x0, #40]
    add     x27, x0, #48
    stp     x21, x22, [x27, #Eth1Snapshot_blocks]
    str     x25, [x27, #Eth1Snapshot_leaves]
    add     x0, x27, #Eth1Snapshot__fixed   /* the blocks */
    ldr     x1, [x19, #Node_eth1_blocks]
    add     x1, x19, x1
    mov     x9, #Eth1Block__mem
    mul     x2, x21, x9
    add     x27, x0, x2
    bl      lantern_copy
    mov     x0, x27                         /* the deposits */
    ldr     x1, [x19, #Node_eth1_deposits]
    add     x1, x19, x1
    mov     x9, #Eth1Deposit__mem
    madd    x1, x26, x9, x1
    mul     x2, x22, x9
    add     x27, x0, x2
    bl      lantern_copy
    mov     x0, x27                         /* the leaves */
    ldr     x1, [x19, #Node_eth1_leaves]
    add     x1, x19, x1
    lsl     x2, x25, #5
    bl      lantern_copy
    mov     x0, x28
    LEAVE 0
END_FUNCTION lantern_node_eth1_snapshot
