/*
 * The eth1 follower of the node, RISC-V: in the common object. Requirements: docs/reference/node.md
 * (the eth1 follower, Block production) and docs/reference/eth1.md.
 *
 * The step's helpers read the node from s1, the store from s2, the scratch from s5 and the
 * actions from s6.
 */

# With NODE_FLAG_ENGINE and NODE_FLAG_ETH1, after the head: when the store's epoch + 1 is above
# eth1_check_epoch and the head's post-state is held, an ETH1_CHECK work of it. s3 the epoch + 1.
LOCAL_FUNCTION lantern_node_eth1_check_due
    ENTER 0
    ld      t0, Node_flags(s1)
    andi    t1, t0, NODE_FLAG_ENGINE
    beqz    t1, 9f
    li      t1, NODE_FLAG_ETH1
    and     t1, t0, t1
    beqz    t1, 9f
    mv      a0, s2
    call    lantern_node_store_slot
    li      t0, SLOTS_PER_EPOCH
    divu    s3, a0, t0
    addi    s3, s3, 1
    LDQ     t0, s1, Node_eth1_check_epoch
    bleu    s3, t0, 9f
    addi    a0, s1, Node_head_root
    call    lantern_node_find_block
    li      t0, -1
    beq     a0, t0, 9f
    ld      a1, NodeBlock_state_id(a1)
    beqz    a1, 9f
    STQ     s3, s1, Node_eth1_check_epoch
    li      a0, NODE_WORK_ETH1_CHECK
    li      a2, 0
    li      a3, 0
    li      a4, 0
    li      a5, 0
    call    lantern_node_work
9:  LEAVE 0
END_FUNCTION lantern_node_eth1_check_due

# a0 = the start in seconds of the voting period of the store's slot (phase0 voting_period_start_time). Uses t0-t2, a7.
LOCAL_FUNCTION lantern_node_eth1_period
    FRAME 0
    mv      a0, s2
    call    lantern_node_store_slot
    li      t0, EPOCHS_PER_ETH1_VOTING_PERIOD * SLOTS_PER_EPOCH
    divu    t1, a0, t0
    mul     t1, t1, t0
    LDQ     t2, s1, Node_config + CONFIG_SLOT_DURATION_MS
    mul     t1, t1, t2
    ld      t2, Store_genesis_time_ms(s2)
    add     t1, t1, t2
    li      t0, 1000
    divu    a0, t1, t0
    UNFRAME 0
END_FUNCTION lantern_node_eth1_period

# a0 = 2 * SECONDS_PER_ETH1_BLOCK * ETH1_FOLLOW_DISTANCE of the config. Uses t0, a7.
LOCAL_FUNCTION lantern_node_eth1_reach
    UNWIND_END_PROLOGUE
    LDQ     t0, s1, Node_config + CONFIG_SECONDS_PER_ETH1_BLOCK
    LDQ     a0, s1, Node_config + CONFIG_ETH1_FOLLOW_DISTANCE
    mul     a0, a0, t0
    slli    a0, a0, 1
    ret
END_FUNCTION lantern_node_eth1_reach

# With eth1_state 1, the next eth1 call (node.md, the eth1 follower): the latest block when its poll
# is due, else the logs up to the follow head, else a block of the window. a0 = 1 when one went,
# else 0. s3 the blocks, s4 their count, s7 the follow head, s8 a block's number or the logs' first,
# s9 the logs' last, s10 the method.
LOCAL_FUNCTION lantern_node_eth1_next
    ENTER 0
    LDQ     t0, s1, Node_eth1_state
    li      t1, 1
    bne     t0, t1, 8f
    li      s10, ENGINE_METHOD_ETH_BLOCK
    li      s8, -1
    li      s9, 0
    LDQ     t0, s1, Node_eth1_head_ms       # the latest: at first, then each SECONDS_PER_ETH1_BLOCK
    beqz    t0, 5f
    LDQ     t1, s1, Node_config + CONFIG_SECONDS_PER_ETH1_BLOCK
    li      t2, 1000
    mul     t1, t1, t2
    add     t0, t0, t1
    ld      t1, Node_time_ms(s1)
    bgeu    t1, t0, 5f
    LDQ     s7, s1, Node_eth1_head          # the follow head
    LDQ     t0, s1, Node_config + CONFIG_ETH1_FOLLOW_DISTANCE
    bltu    s7, t0, 8f
    sub     s7, s7, t0
    LDQ     s8, s1, Node_eth1_logs_to       # the logs up to it
    bgtu    s8, s7, 2f
    li      t0, NODE_ETH1_LOG_BLOCKS - 1
    add     s9, s8, t0
    bleu    s9, s7, 1f
    mv      s9, s7
1:  li      s10, ENGINE_METHOD_ETH_LOGS
    j       5f
2:  PART    s3, s4, s1, Node_eth1_blocks    # the window: the follow head, then up to it, then down
    mv      s8, s7
    beqz    s4, 5f
    addi    t0, s4, -1
    li      t1, Eth1Block__mem
    mul     t0, t0, t1
    add     t0, s3, t0
    ld      t0, Eth1Block_number(t0)
    addi    s8, t0, 1
    bltu    t0, s7, 5f
    ld      s8, Eth1Block_number(s3)
    beqz    s8, 8f
    addi    s8, s8, -1
    call    lantern_node_eth1_period
    mv      s9, a0
    call    lantern_node_eth1_reach
    ld      t0, Eth1Block_timestamp(s3)
    add     t0, t0, a0
    bltu    t0, s9, 8f
    li      s9, 0
5:  mv      a0, s10
    mv      a1, s8
    mv      a2, s9
    call    lantern_node_eth1_send
    LEAVE 0
8:  li      a0, 0
    LEAVE 0
END_FUNCTION lantern_node_eth1_next

# (method a0, number or first a1, last a2): the eth1 call's request, with the id engine_id, in
# lantern_http_post with the JWT of time_ms / 1000, in a NODE_ACT_ENGINE; engine_method the method
# and eth1_call the block asked or the last. a0 = 1 when it went, else 0. s3 the method, s4 the
# number or first, s7 the last, s8 the body, s9 the token, s10 the host. Locals: L the scratch's
# size, L+8 the id, L+16 and L+24 arguments.
LOCAL_FUNCTION lantern_node_eth1_send
    ENTER 32
    mv      s3, a0
    mv      s4, a1
    mv      s7, a2
    li      a0, 48 + 1024 + 7
    call    lantern_node_room
    beqz    a0, 7f
    ld      t0, 0(s5)
    sd      t0, L(sp)
    li      t1, (24 + 512) + (24 + 256) + (24 + 64) + 1024
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    addi    t0, t0, 1024                    # the JWT's scratch keeps 1024 bytes and more
    sd      t0, 0(s5)
    add     s8, s5, t0                      # the body, the token and the host, at the end of scratch
    li      t1, 24 + 512
    sd      t1, 0(s8)
    li      t1, 24
    sd      t1, 8(s8)
    sd      zero, 16(s8)
    addi    s9, s8, 24 + 512
    li      t1, 24 + 256
    sd      t1, 0(s9)
    li      t1, 24
    sd      t1, 8(s9)
    sd      zero, 16(s9)
    addi    s10, s9, 24 + 256
    li      t1, 24 + 64
    sd      t1, 0(s10)
    li      t1, 24
    sd      t1, 8(s10)
    ld      a2, Node_engine_host_len(s1)
    sd      a2, 16(s10)
    addi    a0, s10, 24
    addi    a1, s1, Node_engine_host
    call    lantern_copy
    ld      t0, Node_engine_id(s1)
    sd      t0, (L + 8)(sp)
    li      t0, ENGINE_METHOD_ETH_LOGS
    beq     s3, t0, 1f
    sd      s4, (L + 16)(sp)
    addi    a0, sp, (L + 16)
    addi    a1, sp, (L + 8)
    mv      a2, s8
    call    lantern_eth_get_block_by_number
    j       2f
1:  sd      s4, (L + 16)(sp)
    sd      s7, (L + 24)(sp)
    ADDQ    a0, s1, Node_config + CONFIG_DEPOSIT_CONTRACT_ADDRESS
    addi    a1, sp, (L + 16)
    addi    a2, sp, (L + 24)
    addi    a3, sp, (L + 8)
    mv      a4, s8
    call    lantern_eth_get_deposit_logs
2:  bnez    a0, 8f
    ld      t0, Node_time_ms(s1)            # the JWT at the time in seconds
    li      t1, 1000
    divu    t0, t0, t1
    sd      t0, (L + 16)(sp)
    addi    a0, s1, Node_jwt_secret
    addi    a1, sp, (L + 16)
    mv      a2, s5
    mv      a3, s9
    call    lantern_jwt_token
    bnez    a0, 8f
    li      a0, NODE_ACT_ENGINE             # the request in the action
    li      a1, 48 + 1024
    call    lantern_node_act
    sd      zero, 16(a0)
    li      t0, 24 + 1024
    sd      t0, 24(a0)
    li      t0, 24
    sd      t0, 32(a0)
    sd      zero, 40(a0)
    addi    a3, a0, 24
    mv      a0, s10
    mv      a1, s9
    mv      a2, s8
    call    lantern_http_post
    ld      t0, Node_engine_id(s1)          # the call in flight
    addi    t0, t0, 1
    sd      t0, Node_engine_id(s1)
    sd      s3, Node_engine_method(s1)
    mv      t0, s4
    li      t1, ENGINE_METHOD_ETH_LOGS
    bne     s3, t1, 3f
    mv      t0, s7
3:  STQ     t0, s1, Node_eth1_call
    ld      t0, L(sp)
    sd      t0, 0(s5)
    li      a0, 1
    LEAVE 32
8:  ld      t0, L(sp)
    sd      t0, 0(s5)
7:  li      a0, 0
    LEAVE 32
END_FUNCTION lantern_node_eth1_send

# The eth1 call in flight answered: the body a0 (a ByteList in scratch, which stays short) with its
# EngineResponse a1 (node.md, the eth1 follower). A result the follower refuses, or a block of
# another number, makes eth1_head_ms time_ms. s3 the deposits' list, s4 an entry, s7 the entries
# left, s8 a leaf, s9 a part's entry. Locals: L the result's ByteList (24), L+24 an Eth1Block (88),
# L+112 the scratch's size.
LOCAL_FUNCTION lantern_node_eth1_answer
    ENTER 128
    ld      t0, 8(a0)                       # the result's ByteList: its bytes in the body
    add     t0, a0, t0
    ld      t1, EngineResponse_result_offset(a1)
    add     t0, t0, t1
    ld      t1, EngineResponse_result_length(a1)
    addi    t2, sp, L
    sub     t0, t0, t2
    sd      t0, 8(t2)
    sd      t1, 16(t2)
    add     t0, t0, t1
    sd      t0, 0(t2)
    ld      t0, Node_engine_method(s1)
    li      t1, ENGINE_METHOD_ETH_LOGS
    beq     t0, t1, 20f
    addi    a0, sp, L                       # a block
    addi    a1, sp, (L + 24)
    call    lantern_eth1_block
    bnez    a0, 80f
    LDQ     t0, s1, Node_eth1_call
    ld      t1, (L + 24 + Eth1Block_number)(sp)
    li      t2, -1
    bne     t0, t2, 10f
    STQ     t1, s1, Node_eth1_head          # the latest
    ld      t0, Node_time_ms(s1)
    STQ     t0, s1, Node_eth1_head_ms
    LEAVE 128
10: bne     t1, t0, 80f
    addi    a0, sp, (L + 24)
    call    lantern_node_eth1_block_add
    LEAVE 128
20: ld      t0, 0(s5)                       # the logs: the deposits' list in scratch
    sd      t0, (L + 112)(sp)
    li      t1, 64 + 24
    bltu    t0, t1, 80f
    addi    t0, t0, -64
    andi    t0, t0, -8
    li      t1, 64
    sd      t1, 0(s5)
    addi    s3, s5, 64
    sd      t0, 0(s3)
    addi    a0, sp, L
    mv      a1, s3
    call    lantern_eth1_deposit_logs
    bnez    a0, 85f
    ld      t0, 16(s3)
    li      t1, Eth1Deposit__mem
    divu    s7, t0, t1
    LDQ     t0, s1, Node_eth1_leaves        # room for them all
    LDQ     t2, s1, Node_eth1_deposits
    sub     t0, t0, t2
    divu    t0, t0, t1
    LDQ     t2, s1, Node_eth1_deposits + 8
    add     t2, t2, s7
    bgtu    t2, t0, 85f
    addi    s4, s3, 24
30: beqz    s7, 40f                         # each deposit of the next index joins; one below it is skipped
    LDQ     t1, s1, Node_eth1_deposits + 8
    ld      t0, Eth1Deposit_index(s4)
    bltu    t0, t1, 39f
    bgtu    t0, t1, 85f
    addi    t0, t1, 1
    STQ     t0, s1, Node_eth1_deposits + 8
    li      t2, Eth1Deposit__mem
    mul     t1, t1, t2
    LDQ     t2, s1, Node_eth1_deposits
    add     t1, t1, t2
    add     a0, s1, t1
    mv      a1, s4
    li      a2, Eth1Deposit__mem
    call    lantern_copy
    LDQ     t1, s1, Node_eth1_leaves + 8    # its leaf, then the tree
    addi    t0, t1, 1
    STQ     t0, s1, Node_eth1_leaves + 8
    slli    t1, t1, 5
    LDQ     t2, s1, Node_eth1_leaves
    add     t1, t1, t2
    add     s8, s1, t1
    addi    a0, s4, Eth1Deposit_data
    mv      a1, s8
    call    lantern_deposit_leaf
    ADDQ    a0, s1, Node_eth1_tree
    mv      a1, s8
    call    lantern_deposit_tree_push
    bnez    a0, 85f
    li      t0, 1                           # after the block's last deposit: its count
    beq     s7, t0, 31f
    ld      t0, (Eth1Deposit__mem + Eth1Deposit_block_number)(s4)
    ld      t1, Eth1Deposit_block_number(s4)
    beq     t0, t1, 39f
31: LDQ     t1, s1, Node_eth1_counts + 8
    addi    t0, t1, 1
    STQ     t0, s1, Node_eth1_counts + 8
    li      t2, Eth1Count__mem
    mul     t1, t1, t2
    LDQ     t2, s1, Node_eth1_counts
    add     t1, t1, t2
    add     s9, s1, t1
    ld      t0, Eth1Deposit_block_number(s4)
    sd      t0, Eth1Count_number(s9)
    ADDQ    a0, s1, Node_eth1_tree
    ld      t0, DepositTree_count(a0)
    sd      t0, Eth1Count_count(s9)
    addi    a1, s9, Eth1Count_root
    call    lantern_deposit_tree_root
39: addi    s4, s4, Eth1Deposit__mem
    addi    s7, s7, -1
    j       30b
40: ld      t0, (L + 112)(sp)               # the range is in
    sd      t0, 0(s5)
    LDQ     t0, s1, Node_eth1_call
    addi    t0, t0, 1
    STQ     t0, s1, Node_eth1_logs_to
    LEAVE 128
85: ld      t0, (L + 112)(sp)
    sd      t0, 0(s5)
80: ld      t0, Node_time_ms(s1)            # a failed call: the next head poll
    STQ     t0, s1, Node_eth1_head_ms
    LEAVE 128
END_FUNCTION lantern_node_eth1_answer

# The Eth1Block a0 of an answer, its number, hash and timestamp set, joins eth1_blocks after the
# highest or before the lowest (node.md, the eth1 follower), its count and root those of the last
# eth1_counts entry at or below its number. s3 the block, s4 its number, s7 the entries, s8 their
# count, s9 the capacity, s10 an index. Locals: L a DepositTree count of 0, L+8 the period start,
# L+16 the reach.
LOCAL_FUNCTION lantern_node_eth1_block_add
    ENTER 32
    mv      s3, a0
    ld      s4, Eth1Block_number(s3)
    PART    t0, t1, s1, Node_eth1_counts    # its count and root
1:  beqz    t1, 2f
    addi    t1, t1, -1
    li      t2, Eth1Count__mem
    mul     t2, t1, t2
    add     t2, t0, t2
    ld      t3, Eth1Count_number(t2)
    bgtu    t3, s4, 1b
    ld      t3, Eth1Count_count(t2)
    sd      t3, Eth1Block_deposit_count(s3)
    addi    t0, s3, Eth1Block_deposit_root
    addi    t1, t2, Eth1Count_root
    COPY32  t0, t1
    j       3f
2:  sd      zero, Eth1Block_deposit_count(s3)   # none: the root of no deposits
    sd      zero, L(sp)
    addi    a0, sp, L
    addi    a1, s3, Eth1Block_deposit_root
    call    lantern_deposit_tree_root
3:  PART    s7, s8, s1, Node_eth1_blocks
    LDQ     t0, s1, Node_eth1_deposits
    LDQ     t1, s1, Node_eth1_blocks
    sub     t0, t0, t1
    li      t1, Eth1Block__mem
    divu    s9, t0, t1
    beqz    s9, 9f
    beqz    s8, 5f
    addi    t0, s8, -1                      # after the highest
    li      t1, Eth1Block__mem
    mul     t0, t0, t1
    add     t0, s7, t0
    ld      t0, Eth1Block_number(t0)
    addi    t0, t0, 1
    beq     s4, t0, 5f
    ld      t0, Eth1Block_number(s7)        # before the lowest, with room
    addi    t0, t0, -1
    bne     s4, t0, 9f
    bgeu    s8, s9, 9f
    mv      s10, s8                         # each entry one up, from the highest
4:  beqz    s10, 41f
    addi    s10, s10, -1
    li      t1, Eth1Block__mem
    mul     t0, s10, t1
    add     a1, s7, t0
    add     a0, a1, t1
    li      a2, Eth1Block__mem
    call    lantern_copy
    j       4b
41: LDQ     t0, s1, Node_eth1_blocks + 8
    addi    t0, t0, 1
    STQ     t0, s1, Node_eth1_blocks + 8
    mv      a0, s7
    mv      a1, s3
    li      a2, Eth1Block__mem
    call    lantern_copy
    j       6f
5:  bltu    s8, s9, 51f                     # after the highest; no room: the lowest goes first
    call    lantern_node_eth1_block_drop
51: PART    s7, s8, s1, Node_eth1_blocks
    li      t1, Eth1Block__mem
    mul     t0, s8, t1
    add     a0, s7, t0
    addi    t0, s8, 1
    STQ     t0, s1, Node_eth1_blocks + 8
    mv      a1, s3
    li      a2, Eth1Block__mem
    call    lantern_copy
6:  call    lantern_node_eth1_period                # while the second entry is before the period's reach, the lowest goes
    sd      a0, (L + 8)(sp)
    call    lantern_node_eth1_reach
    sd      a0, (L + 16)(sp)
7:  PART    t0, t1, s1, Node_eth1_blocks
    li      t2, 1
    bleu    t1, t2, 9f
    ld      t2, (Eth1Block__mem + Eth1Block_timestamp)(t0)
    ld      t3, (L + 16)(sp)
    add     t2, t2, t3
    ld      t3, (L + 8)(sp)
    bgeu    t2, t3, 9f
    call    lantern_node_eth1_block_drop
    j       7b
9:  LEAVE 32
END_FUNCTION lantern_node_eth1_block_add

# The lowest eth1_blocks entry goes: each other one down. s3 the entries, s4 the count, s7 the index.
LOCAL_FUNCTION lantern_node_eth1_block_drop
    ENTER 0
    PART    s3, s4, s1, Node_eth1_blocks
    beqz    s4, 9f
    li      s7, 1
1:  bgeu    s7, s4, 2f
    li      t1, Eth1Block__mem
    mul     t0, s7, t1
    add     a1, s3, t0
    sub     a0, a1, t1
    li      a2, Eth1Block__mem
    call    lantern_copy
    addi    s7, s7, 1
    j       1b
2:  addi    s4, s4, -1
    STQ     s4, s1, Node_eth1_blocks + 8
9:  LEAVE 0
END_FUNCTION lantern_node_eth1_block_drop

# a0 = the bytes of the follower's Eth1Snapshot (node.md): with eth1_state 1 its blocks, the
# deposits from eth1_deposit_index, at most MAX_DEPOSITS, and every leaf; else none. a1 the blocks,
# a2 the deposits, a3 the leaves, a4 the first deposit. Uses t0-t2, a7.
LOCAL_FUNCTION lantern_node_eth1_snapshot_size
    UNWIND_END_PROLOGUE
    li      a1, 0
    li      a2, 0
    li      a3, 0
    li      a4, 0
    LDQ     t0, s1, Node_eth1_state
    li      t1, 1
    bne     t0, t1, 1f
    LDQ     a1, s1, Node_eth1_blocks + 8
    LDQ     a4, s1, Node_eth1_deposit_index
    LDQ     t0, s1, Node_eth1_deposits + 8
    bltu    t0, a4, 2f
    sub     a2, t0, a4
2:  li      t0, MAX_DEPOSITS
    bleu    a2, t0, 3f
    mv      a2, t0
3:  LDQ     a3, s1, Node_eth1_leaves + 8
1:  li      t0, Eth1Block__mem
    mul     a0, a1, t0
    addi    a0, a0, Eth1Snapshot__fixed
    li      t0, Eth1Deposit__mem
    mul     t1, a2, t0
    add     a0, a0, t1
    slli    t1, a3, 5
    add     a0, a0, t1
    ret
END_FUNCTION lantern_node_eth1_snapshot_size

# a0 = the id of a new BYTES_PUT of the follower's Eth1Snapshot (node.md, NODE_PRODUCE_ETH1). s3
# the blocks, s4 the deposits, s7 the leaves, s8 the first deposit, s9 the snapshot, s10 the id.
LOCAL_FUNCTION lantern_node_eth1_snapshot
    ENTER 0
    call    lantern_node_new_id
    mv      s10, a0
    call    lantern_node_eth1_snapshot_size
    mv      s3, a1
    mv      s4, a2
    mv      s7, a3
    mv      s8, a4
    mv      s9, a0
    addi    a1, a0, 48 + 7
    andi    a1, a1, -8
    li      a0, NODE_ACT_BYTES_PUT
    call    lantern_node_act
    sd      s10, 16(a0)
    ld      t0, 0(a0)
    addi    t0, t0, -24
    sd      t0, 24(a0)
    li      t0, 24
    sd      t0, 32(a0)
    sd      s9, 40(a0)
    addi    s9, a0, 48
    sd      s3, Eth1Snapshot_blocks(s9)
    sd      s4, Eth1Snapshot_deposits(s9)
    sd      s7, Eth1Snapshot_leaves(s9)
    addi    a0, s9, Eth1Snapshot__fixed     # the blocks
    LDQ     t0, s1, Node_eth1_blocks
    add     a1, s1, t0
    li      t0, Eth1Block__mem
    mul     a2, s3, t0
    add     s9, a0, a2
    call    lantern_copy
    mv      a0, s9                          # the deposits
    LDQ     t0, s1, Node_eth1_deposits
    add     a1, s1, t0
    li      t0, Eth1Deposit__mem
    mul     t1, s8, t0
    add     a1, a1, t1
    mul     a2, s4, t0
    add     s9, a0, a2
    call    lantern_copy
    mv      a0, s9                          # the leaves
    LDQ     t0, s1, Node_eth1_leaves
    add     a1, s1, t0
    slli    a2, s7, 5
    call    lantern_copy
    mv      a0, s10
    LEAVE 0
END_FUNCTION lantern_node_eth1_snapshot
