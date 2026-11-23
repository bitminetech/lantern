# The light client data of the node, RISC-V: in the common object. Requirements: docs/reference/node.md,
# beacon-api.md and light-client.md.

# L2: (route, connection, flags) -> a0: a light client read of NODE_EV_API (node.md): a
# NODE_WORK_API_ENCODE with the light client store as state_c; 0. The node s1, the actions s6. s2
# the route, s3 the connection, s4 the answer flags, s5 the operation, s7 the bytes' id. Locals: L
# a ByteList of the bytes put.
LOCAL_FUNCTION node_api_lc
    ENTER 64
    mv      s2, a0
    mv      s3, a1
    mv      s4, a2
    ld      t0, ApiRoute_response(s2)
    li      t1, API_TYPE_SSZ
    bne     t0, t1, 1f
    ori     s4, s4, API_ANSWER_SSZ
1:  ld      s5, ApiRoute_op(s2)
    li      s7, 0
    li      t0, API_OP_GET_LIGHT_CLIENT_BOOTSTRAP
    bne     s5, t0, 2f
    addi    t0, sp, L                       # getLightClientBootstrap: the root's 32 bytes
    li      t1, 56
    sd      t1, 0(t0)
    li      t1, 24
    sd      t1, 8(t0)
    li      t1, 32
    sd      t1, 16(t0)
    addi    t1, t0, 24
    addi    t2, s2, ApiRoute_id_root
    COPY32  t1, t2
    j       3f
2:  li      t0, API_OP_GET_LIGHT_CLIENT_UPDATES_BY_RANGE
    bne     s5, t0, 4f
    ld      t0, ApiRoute_start_period(s2)   # the periods: start, and past the last
    ld      t1, ApiRoute_count(s2)
    li      t2, MAX_REQUEST_LIGHT_CLIENT_UPDATES
    bleu    t1, t2, 21f
    mv      t1, t2
21: add     t1, t0, t1
    bgeu    t1, t0, 22f
    li      t1, -1
22: addi    t2, sp, L
    li      t3, 40
    sd      t3, 0(t2)
    li      t3, 24
    sd      t3, 8(t2)
    li      t3, 16
    sd      t3, 16(t2)
    sd      t0, 24(t2)
    sd      t1, 32(t2)
3:  addi    a0, sp, L
    call    node_put
    mv      s7, a0
4:  li      a0, NODE_WORK_API_ENCODE
    li      a1, 0
    li      a2, 0
    mv      a3, s7
    mv      a4, s3
    slli    a5, s4, 8
    or      a5, a5, s5
    call    node_work
    li      t0, NODE_LC_ID
    sd      t0, NodeAction_state_c(a0)
    li      a0, 0
    LEAVE 64
END_FUNCTION node_api_lc

# L2: (lc, work, data, scratch, view) -> status, the node s1: the light client read of a
# NODE_WORK_API_ENCODE (node.md) into the view: for getLightClientUpdatesByRange its store, periods,
# node, JSON room and cursor, which its body reads; else the object's SSZ bytes (ApiView_lc_bytes),
# its fork, and as JSON its JSON (ApiView_lc_json). With none, ApiView_status 404; a fault of the
# JSON, 500. LANTERN_INVALID_EVENT without the store or the work's bytes; LANTERN_BUFFER_TOO_SMALL
# with too little scratch. s2 lc, s3 work, s4 data, s5 scratch, s7 view, s8 the kind, s9 the
# object, s10 the JSON; the node in s1 kept. Locals: L the fork, L + 8 1 for SSZ, L + 16 the cursor.
LOCAL_FUNCTION node_api_lc_read
    ENTER 32
    mv      s2, a0
    mv      s3, a1
    mv      s4, a2
    mv      s5, a3
    mv      s7, a4
    beqz    s2, 97f
    ld      t0, NodeAction_arg(s3)
    srli    t1, t0, 8
    andi    t1, t1, API_ANSWER_SSZ
    snez    t1, t1
    sd      t1, (L + 8)(sp)
    andi    t0, t0, 255
    li      s8, LC_OBJECT_FINALITY_UPDATE
    li      t1, API_OP_GET_LIGHT_CLIENT_FINALITY_UPDATE
    beq     t0, t1, 2f
    li      s8, LC_OBJECT_OPTIMISTIC_UPDATE
    li      t1, API_OP_GET_LIGHT_CLIENT_OPTIMISTIC_UPDATE
    beq     t0, t1, 2f
    li      s8, LC_OBJECT_UPDATE
    li      t2, 16
    li      t1, API_OP_GET_LIGHT_CLIENT_UPDATES_BY_RANGE
    beq     t0, t1, 1f
    li      s8, LC_OBJECT_BOOTSTRAP
    li      t2, 32
1:  beqz    s4, 97f                         # the root, or the two periods
    ld      t0, 16(s4)
    bne     t0, t2, 97f
2:  ld      t0, 0(s5)                       # the object at the end of scratch
    li      t1, 24 + LC_UPDATE_ROOM
    bltu    t0, t1, 98f
    sub     t0, t0, t1
    sd      t0, 0(s5)
    add     s9, s5, t0
    sd      t1, 0(s9)
    STQ     s9, s7, ApiView_lc_bytes
    STQ     zero, s7, ApiView_lc_json
    ld      t0, 0(s5)                       # its JSON's room, and a cursor
    li      t1, 24 + 4 * LC_UPDATE_ROOM + 4096 + JSON_CURSOR_SIZE
    bltu    t0, t1, 98f
    sub     t0, t0, t1
    sd      t0, 0(s5)
    add     s10, s5, t0
    li      t1, 24 + 4 * LC_UPDATE_ROOM + 4096
    sd      t1, 0(s10)
    li      t2, 24
    sd      t2, 8(s10)
    sd      zero, 16(s10)
    add     t2, s10, t1
    sd      t2, (L + 16)(sp)
    li      t0, LC_OBJECT_UPDATE
    bne     s8, t0, 3f
    STQ     s2, s7, ApiView_lc_store        # getLightClientUpdatesByRange: its body reads them
    STQ     t2, s7, ApiView_lc_cursor
    STQ     s10, s7, ApiView_lc_json
    ld      t0, (L + 8)(sp)
    STQ     t0, s7, ApiView_lc_ssz
    ld      t0, 8(s4)
    add     t0, s4, t0
    ld      t1, 0(t0)
    STQ     t1, s7, ApiView_lc_start
    ld      t1, 8(t0)
    STQ     t1, s7, ApiView_lc_end
    STQ     s1, s7, ApiView_node
    li      a0, LANTERN_OK
    LEAVE 32
3:  mv      a0, s2
    mv      a1, s8
    li      a2, 0
    bnez    s8, 31f
    ld      t0, 8(s4)                       # the bootstrap: of the root
    add     a2, s4, t0
31: mv      a3, s9
    addi    a4, sp, L
    call    lantern_lc_read
    li      t0, LANTERN_NO_STATE_ANSWER
    beq     a0, t0, 80f
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 98f
    bnez    a0, 81f
    ld      t0, L(sp)
    sd      t0, ApiView_fork(s7)
    ld      t0, (L + 8)(sp)
    bnez    t0, 9f
    ld      a0, (L + 16)(sp)
    li      a1, JSON_CURSOR_SIZE
    call    lantern_zero
    li      a0, NODE_JSON_LC_BOOTSTRAP      # the JSON of the kind
    li      t0, LC_OBJECT_FINALITY_UPDATE
    bne     s8, t0, 32f
    li      a0, NODE_JSON_LC_FINALITY_UPDATE
32: li      t0, LC_OBJECT_OPTIMISTIC_UPDATE
    bne     s8, t0, 33f
    li      a0, NODE_JSON_LC_OPTIMISTIC_UPDATE
33: mv      a1, s9
    ld      a2, (L + 16)(sp)
    mv      a3, s10
    ld      t6, L(sp)
    FORK_CALL node_json
    li      t0, LANTERN_JSON_MORE
    beq     a0, t0, 98f
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 98f
    bnez    a0, 81f
    STQ     s10, s7, ApiView_lc_json
9:  li      a0, LANTERN_OK
    LEAVE 32
80: li      t0, 404
    STQ     t0, s7, ApiView_status
    li      a0, LANTERN_OK
    LEAVE 32
81: li      t0, 500
    STQ     t0, s7, ApiView_status
    li      a0, LANTERN_OK
    LEAVE 32
97: li      a0, LANTERN_INVALID_EVENT
    LEAVE 32
98: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION node_api_lc_read

# L2: the body of getLightClientUpdatesByRange (beacon-api.md) of the view s4 (its node
# ApiView_node), with the writer of api_put: from the first period with an update, each update to
# the first period of none. Locals: 0 the fork, 8 1 once an update is in, 16 the period, 24 a
# chunk's length, 32 an epoch, 40 a digest.
LOCAL_FUNCTION api_lc_updates_body
    FRAME 48
    sd      zero, 0(sp)
    sd      zero, 8(sp)
    LDQ     t0, s4, ApiView_lc_start
    sd      t0, 16(sp)
    LDQ     t0, s4, ApiView_lc_ssz
    bnez    t0, 1f
    API_LIT api_lc_open
1:  ld      t0, 16(sp)
    LDQ     t1, s4, ApiView_lc_end
    bgeu    t0, t1, 8f
    LDQ     a0, s4, ApiView_lc_store
    li      a1, LC_OBJECT_UPDATE
    ld      a2, 16(sp)
    LDQ     a3, s4, ApiView_lc_bytes
    li      t0, 24 + LC_UPDATE_ROOM
    sd      t0, 0(a3)
    mv      a4, sp
    call    lantern_lc_read
    beqz    a0, 2f
    ld      t0, 8(sp)                       # none: after an update, the end; before, the next period
    bnez    t0, 8f
    ld      t0, 16(sp)
    addi    t0, t0, 1
    sd      t0, 16(sp)
    j       1b
2:  LDQ     t0, s4, ApiView_lc_ssz
    beqz    t0, 3f
    LDQ     t0, s4, ApiView_lc_bytes        # SSZ: response_chunk_len, the context, the bytes
    ld      t1, 16(t0)
    addi    t1, t1, 4
    sd      t1, 24(sp)
    addi    a0, sp, 24
    li      a1, 8
    call    api_put
    LDQ     t0, s4, ApiView_lc_bytes
    ld      t1, 8(t0)
    add     t0, t0, t1
    ld      t2, 0(sp)
    li      t3, FORK_CAPELLA
    bltu    t2, t3, 21f
    lwu     t1, 0(t0)
    add     t0, t0, t1
21: ld      t0, 0(t0)                       # attested_header.beacon.slot: its epoch's fork digest
    li      t1, SLOTS_PER_EPOCH
    divu    t0, t0, t1
    sd      t0, 32(sp)
    LDQ     a3, s4, ApiView_lc_json         # its room, as the digest's scratch
    li      t0, 24 + 4 * LC_UPDATE_ROOM + 4096
    sd      t0, 0(a3)
    LDQ     t0, s4, ApiView_node
    addi    a0, t0, Node_genesis_validators_root
    addi    a1, sp, 32
    li      t1, Node_config
    add     a2, t0, t1
    addi    a4, sp, 40
    ld      t6, 0(sp)
    FORK_CALL compute_fork_digest
    addi    a0, sp, 40
    li      a1, 4
    call    api_put
    LDQ     t0, s4, ApiView_lc_bytes
    ld      t1, 8(t0)
    add     a0, t0, t1
    ld      a1, 16(t0)
    call    api_put
    j       4f
3:  ld      t0, 8(sp)                       # JSON: {"version":…,"data":…}, with , between
    beqz    t0, 31f
    API_LIT api_lc_comma
31: API_LIT api_j_version
    ld      a0, 0(sp)
    call    api_fork_name
    API_LIT api_g_data
    LDQ     t0, s4, ApiView_lc_json
    li      t1, 24 + 4 * LC_UPDATE_ROOM + 4096
    sd      t1, 0(t0)
    li      t1, 24
    sd      t1, 8(t0)
    sd      zero, 16(t0)
    LDQ     a0, s4, ApiView_lc_cursor
    li      a1, JSON_CURSOR_SIZE
    call    lantern_zero
    li      a0, NODE_JSON_LC_UPDATE
    LDQ     a1, s4, ApiView_lc_bytes
    LDQ     a2, s4, ApiView_lc_cursor
    LDQ     a3, s4, ApiView_lc_json
    ld      t6, 0(sp)
    FORK_CALL node_json
    bnez    a0, 8f
    LDQ     t0, s4, ApiView_lc_json
    ld      t1, 8(t0)
    add     a0, t0, t1
    ld      a1, 16(t0)
    call    api_put
    API_LIT api_end1
4:  li      t0, 1
    sd      t0, 8(sp)
    ld      t0, 16(sp)
    addi    t0, t0, 1
    sd      t0, 16(sp)
    j       1b
8:  LDQ     t0, s4, ApiView_lc_ssz
    bnez    t0, 9f
    API_LIT api_lc_close
9:  UNFRAME 48
END_FUNCTION api_lc_updates_body

# L2: (node, store, work, state_a, data, state_c, scratch, event) -> status: a NODE_WORK_LC_BLOCK or
# NODE_WORK_LC_HEAD of lantern_node_run (node.md). s1 node, s2 store, s3 work, s4 state_a, s5 data,
# s6 the LcStore, s7 scratch, s8 event.
LOCAL_FUNCTION node_run_lc
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    mv      s7, a6
    mv      s8, a7
    beqz    s6, 97f
    ld      t0, NodeAction_work_kind(s3)
    li      t1, NODE_WORK_LC_HEAD
    beq     t0, t1, 2f
    beqz    s4, 97f                         # LC_BLOCK: lantern_lc_on_block of the post-state and the block
    beqz    s5, 97f
    mv      a0, s6
    li      t0, Node_config
    add     a1, s1, t0
    mv      a2, s4
    mv      a3, s5
    LDQ     a4, s1, Node_config + CONFIG_STATE_CACHE  # the StateCache of the node's config
    mv      a5, s7
    call    lantern_lc_on_block
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 9f
    sd      a0, NodeEvent_result(s8)
    li      a0, LANTERN_OK
    LEAVE 0
2:  mv      a0, s6                          # LC_HEAD: lantern_lc_on_head of the head and the store's finalized checkpoint
    li      t0, Node_config
    add     a1, s1, t0
    addi    a2, s1, Node_head_root
    addi    a3, s2, Store_finalized_checkpoint
    mv      a4, s7
    call    lantern_lc_on_head
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 9f
    sd      a0, NodeEvent_result(s8)
    bnez    a0, 8f
    mv      a0, s6                          # the latest update's fields
    mv      a1, s8
    call    node_lc_slots
8:  li      a0, LANTERN_OK
    LEAVE 0
9:  LEAVE 0
97: li      a0, LANTERN_INVALID_EVENT
    LEAVE 0
END_FUNCTION node_run_lc

# L1: (event, topic) -> a0: 1 when the update of the fields of the light client work's event a0 is
# new for the topic a1 (node.md, The light client gossip), else 0. s1 the node. Uses t0, t1, a7.
LOCAL_FUNCTION node_lc_new
    UNWIND_END_PROLOGUE
    li      t0, GOSSIP_LIGHT_CLIENT_FINALITY_UPDATE
    bne     a1, t0, 2f
    ld      t0, NodeEvent_index(a0)         # finality: a higher finalized slot, or the same with a new supermajority
    LDQ     t1, s1, Node_lc_finality_slot
    bgtu    t0, t1, 8f
    bne     t0, t1, 9f
    LDQ     t1, s1, Node_lc_finality_super
    bnez    t1, 9f
    ld      t0, (NodeEvent_root + 8)(a0)
    beqz    t0, 9f
    j       8f
2:  ld      t0, NodeEvent_root(a0)          # optimistic: a higher attested slot
    LDQ     t1, s1, Node_lc_optimistic_slot
    bleu    t0, t1, 9f
8:  li      a0, 1
    ret
9:  li      a0, 0
    ret
END_FUNCTION node_lc_new

# L1: the fields of the topic a1 take the update of the light client work's event a0 (node.md, The light client gossip). s1 the node. Uses t0, t1, a7.
LOCAL_FUNCTION node_lc_set
    UNWIND_END_PROLOGUE
    li      t1, GOSSIP_LIGHT_CLIENT_FINALITY_UPDATE
    bne     a1, t1, 2f
    ld      t0, NodeEvent_index(a0)
    STQ     t0, s1, Node_lc_finality_slot
    ld      t0, (NodeEvent_root + 8)(a0)
    STQ     t0, s1, Node_lc_finality_super
    ret
2:  ld      t0, NodeEvent_root(a0)
    STQ     t0, s1, Node_lc_optimistic_slot
    ret
END_FUNCTION node_lc_set

# L1: a0 = the due time in Unix ms of an update of signature slot a0 (node.md, The light client
# gossip): genesis time + the slot times SLOT_DURATION_MS + get_sync_message_due_ms(). s1 the
# node, s2 the store. Uses t0-t2, a7.
LOCAL_FUNCTION node_lc_due_ms
    UNWIND_END_PROLOGUE
    LDQ     t0, s1, Node_config + CONFIG_SLOT_DURATION_MS
    LDQ     t1, s1, Node_config + CONFIG_SYNC_MESSAGE_DUE_BPS
    mul     t1, t1, t0
    li      t2, BASIS_POINTS
    divu    t1, t1, t2
    mul     a0, a0, t0
    add     a0, a0, t1
    LDQ     t0, s2, Store_genesis_time_ms
    add     a0, a0, t0
    ret
END_FUNCTION node_lc_due_ms

# L1: the NODE_EV_WORK_DONE s3 of a NODE_WORK_LC_HEAD (node.md, The light client gossip): with a
# latest update, the bit of each topic it is new for joins lc_pending, and lc_due becomes its due
# time. s1 the node, s2 the store, s6 the actions; s7 the bits.
LOCAL_FUNCTION node_lc_head_done
    ENTER 0
    ld      t0, NodeEvent_result(s3)
    bnez    t0, 9f
    ld      t0, (NodeEvent_root + 16)(s3)
    beqz    t0, 9f
    mv      a0, s3
    li      a1, GOSSIP_LIGHT_CLIENT_FINALITY_UPDATE
    call    node_lc_new
    mv      s7, a0
    mv      a0, s3
    li      a1, GOSSIP_LIGHT_CLIENT_OPTIMISTIC_UPDATE
    call    node_lc_new
    slli    a0, a0, 1
    or      s7, s7, a0
    beqz    s7, 9f
    LDQ     t0, s1, Node_lc_pending
    or      t0, t0, s7
    STQ     t0, s1, Node_lc_pending
    ld      a0, (NodeEvent_root + 24)(s3)
    call    node_lc_due_ms
    STQ     a0, s1, Node_lc_due
9:  LEAVE 0
END_FUNCTION node_lc_head_done

# L1: after the head (node.md, The light client gossip): with lc_pending not 0, time_ms at least
# lc_due and room for two works, a NODE_WORK_LC_PUBLISH of each topic of lc_pending, which becomes
# 0. s1 the node, s6 the actions; s7 the bits.
LOCAL_FUNCTION node_lc_due
    ENTER 0
    LDQ     s7, s1, Node_lc_pending
    beqz    s7, 9f
    LDQ     t0, s1, Node_lc_due
    ld      t1, Node_time_ms(s1)
    bltu    t1, t0, 9f
    li      a0, 2 * NODE_ACT_WORK_SIZE
    call    node_room
    beqz    a0, 9f
    STQ     zero, s1, Node_lc_pending
    andi    t0, s7, 1
    beqz    t0, 1f
    li      a0, GOSSIP_LIGHT_CLIENT_FINALITY_UPDATE
    call    node_lc_publish_work
1:  andi    t0, s7, 2
    beqz    t0, 9f
    li      a0, GOSSIP_LIGHT_CLIENT_OPTIMISTIC_UPDATE
    call    node_lc_publish_work
9:  LEAVE 0
END_FUNCTION node_lc_due

# L1: a NODE_WORK_LC_PUBLISH of the topic a0 with the light client store as state_c.
LOCAL_FUNCTION node_lc_publish_work
    FRAME 16
    mv      a5, a0
    li      a0, NODE_WORK_LC_PUBLISH
    li      a1, 0
    li      a2, 0
    li      a3, 0
    li      a4, 0
    call    node_work
    li      t0, NODE_LC_ID
    sd      t0, NodeAction_state_c(a0)
    UNFRAME 16
END_FUNCTION node_lc_publish_work

# a0 = the event topic of the light client gossip topic in reg. Uses t0, t1.
.macro LC_API_TOPIC reg
    addi    t0, \reg, -GOSSIP_LIGHT_CLIENT_FINALITY_UPDATE
    seqz    t0, t0
    li      a0, API_TOPIC_LIGHT_CLIENT_OPTIMISTIC_UPDATE
    li      t1, API_TOPIC_LIGHT_CLIENT_FINALITY_UPDATE - API_TOPIC_LIGHT_CLIENT_OPTIMISTIC_UPDATE
    mul     t1, t1, t0
    add     a0, a0, t1
.endm

# L1: the NODE_EV_WORK_DONE s3 of a NODE_WORK_LC_PUBLISH (node.md, The light client gossip):
# LANTERN_VALID of an update new for its topic sets the topic's fields, then with
# NODE_FLAG_SUBSCRIBED its bytes at NodeEvent_chunk go out on the topic, and its event. s1 the
# node, s2 the store, s5 the scratch, s6 the actions; s4 the topic.
LOCAL_FUNCTION node_lc_published
    ENTER 0
    ld      t0, NodeEvent_result(s3)
    bnez    t0, 9f
    ld      s4, NodeAction_arg(s3)
    mv      a0, s3
    mv      a1, s4
    call    node_lc_new
    beqz    a0, 9f
    mv      a0, s3
    mv      a1, s4
    call    node_lc_set
    ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_SUBSCRIBED
    beqz    t0, 1f
    mv      a0, s4
    addi    a1, s3, NodeEvent_chunk
    li      a2, 0
    call    node_publish
1:  LC_API_TOPIC s4
    call    node_lc_event
9:  LEAVE 0
END_FUNCTION node_lc_published

# L1: the NODE_EV_WORK_DONE s3 of a NODE_WORK_LC_GOSSIP (node.md, The light client gossip): an
# ACCEPT for LANTERN_VALID of an update new for its topic that is due by time_ms +
# MAXIMUM_GOSSIP_CLOCK_DISPARITY, with the topic's fields and its event; else an IGNORE. Then its
# bytes and the message's entry go. s1 the node, s2 the store, s6 the actions; s4 the topic, s7
# the result.
LOCAL_FUNCTION node_lc_validated
    ENTER 0
    ld      s4, NodeAction_arg(s3)
    li      s7, LIBP2P_IGNORE
    ld      t0, NodeEvent_result(s3)
    bnez    t0, 1f
    mv      a0, s3
    mv      a1, s4
    call    node_lc_new
    beqz    a0, 1f
    ld      a0, (NodeEvent_root + 24)(s3)   # due, with the clock disparity
    call    node_lc_due_ms
    ld      t0, Node_time_ms(s1)
    LDQ     t1, s1, Node_config + CONFIG_MAXIMUM_GOSSIP_CLOCK_DISPARITY
    add     t0, t0, t1
    bltu    t0, a0, 1f
    li      s7, LIBP2P_ACCEPT
    mv      a0, s3
    mv      a1, s4
    call    node_lc_set
    LC_API_TOPIC s4
    call    node_lc_event
1:  ld      a0, NodeAction_target(s3)
    mv      a1, s7
    call    node_validation
    ld      a1, NodeAction_data(s3)
    beqz    a1, 2f
    li      a0, NODE_ACT_BYTES_FREE
    li      a2, 0
    call    node_ids
2:  ld      a0, NodeAction_target(s3)
    call    node_find_message
    li      t0, -1
    beq     a0, t0, 9f
    mv      a0, a1
    call    node_drop_message
9:  LEAVE 0
END_FUNCTION node_lc_validated

# L1: a NODE_WORK_API_EVENT of the topic a0 with the light client store as state_c, when an entry has the topic.
LOCAL_FUNCTION node_lc_event
    FRAME 16
    sd      a0, 0(sp)
    call    node_api_subscribed
    beqz    a0, 9f
    li      a0, NODE_WORK_API_EVENT
    li      a1, 0
    li      a2, 0
    li      a3, 0
    li      a4, 0
    ld      a5, 0(sp)
    call    node_work
    li      t0, NODE_LC_ID
    sd      t0, NodeAction_state_c(a0)
9:  UNFRAME 16
END_FUNCTION node_lc_event

# L2: (out, topic, lc, scratch) -> a0: the text of a light client event (beacon-api.md, eventstream):
# event: <topic> LF data: {"version":…,"data":…} LF LF, into the ByteList out, its count set;
# LANTERN_OK, LANTERN_NO_STATE_ANSWER with no update, LANTERN_BUFFER_TOO_SMALL. The writer's
# registers s6-s9; s1 out, s2 the topic, s3 lc, s4 scratch, s5 the object, s10 the kind. Locals: L
# the fork, L + 8 the scratch's size.
LOCAL_FUNCTION api_lc_event_text
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    ld      t0, 0(s4)
    sd      t0, (L + 8)(sp)
    li      t1, 24 + LC_UPDATE_ROOM + JSON_CURSOR_SIZE  # the object and a cursor at the end of scratch
    bltu    t0, t1, 98f
    sub     t0, t0, t1
    sd      t0, 0(s4)
    add     s5, s4, t0
    li      t1, 24 + LC_UPDATE_ROOM
    sd      t1, 0(s5)
    li      s10, LC_OBJECT_FINALITY_UPDATE
    li      t0, API_TOPIC_LIGHT_CLIENT_FINALITY_UPDATE
    beq     s2, t0, 1f
    li      s10, LC_OBJECT_OPTIMISTIC_UPDATE
1:  mv      a0, s3
    mv      a1, s10
    li      a2, 0
    mv      a3, s5
    addi    a4, sp, L
    call    lantern_lc_read
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 98f
    bnez    a0, 9f
    li      s7, 1                           # the writer
    li      s9, 0
    addi    s6, s1, 24
    ld      t0, 0(s1)
    add     s8, s1, t0
    API_LIT api_ev_event
    li      t0, API_TOPIC_LIGHT_CLIENT_FINALITY_UPDATE
    bne     s2, t0, 2f
    API_LIT api_ev_t_lc_finality
    j       3f
2:  API_LIT api_ev_t_lc_optimistic
3:  API_LIT api_ev_data
    API_LIT api_j_version
    ld      a0, L(sp)
    call    api_fork_name
    API_LIT api_g_data
    bnez    s9, 98f
    addi    t0, s1, 24                      # the JSON after the bytes so far
    sub     t0, s6, t0
    li      t1, 24
    sd      t1, 8(s1)
    sd      t0, 16(s1)
    li      t0, 24 + LC_UPDATE_ROOM
    add     a0, s5, t0
    li      a1, JSON_CURSOR_SIZE
    call    lantern_zero
    li      a0, NODE_JSON_LC_FINALITY_UPDATE
    li      t0, LC_OBJECT_FINALITY_UPDATE
    beq     s10, t0, 4f
    li      a0, NODE_JSON_LC_OPTIMISTIC_UPDATE
4:  mv      a1, s5
    li      t0, 24 + LC_UPDATE_ROOM
    add     a2, s5, t0
    mv      a3, s1
    ld      t6, L(sp)
    FORK_CALL node_json
    li      t0, LANTERN_JSON_MORE
    beq     a0, t0, 98f
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 98f
    bnez    a0, 97f
    ld      t0, 16(s1)
    addi    s6, s1, 24
    add     s6, s6, t0
    API_LIT api_end1
    API_LIT api_ev_lf2
    bnez    s9, 98f
    addi    t0, s1, 24
    sub     t0, s6, t0
    li      t1, 24
    sd      t1, 8(s1)
    sd      t0, 16(s1)
    li      a0, LANTERN_OK
9:  ld      t0, (L + 8)(sp)
    sd      t0, 0(s4)
    LEAVE 16
97: li      a0, LANTERN_INVALID_ENCODING
    j       9b
98: li      a0, LANTERN_BUFFER_TOO_SMALL
    j       9b
END_FUNCTION api_lc_event_text

# L2: (node, work, data, lc, scratch, event, room) -> status: a NODE_WORK_LC_SERVE of
# lantern_node_run (node.md): the response chunks of the light client method arg at NodeEvent_chunk
# of the event. s1 node, s2 work, s3 data, s4 lc, s5 scratch, s6 event, s7 the chunks' ByteList,
# s8 the object at the end of scratch, s9 the period, s10 the end period. Locals: 0 the scratch's
# size, 8 1 once an update is in, 16 an empty ByteList.
LOCAL_FUNCTION node_run_lc_serve
    ENTER 48
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    beqz    s4, 97f
    ld      t0, 0(s5)
    sd      t0, 0(sp)
    addi    t0, a6, -NodeEvent_chunk        # the chunks, in the event
    andi    t0, t0, -8
    li      t1, 64
    bltu    t0, t1, 98f
    addi    s7, s6, NodeEvent_chunk
    sd      t0, 0(s7)
    li      t1, 24
    sd      t1, 8(s7)
    sd      zero, 16(s7)
    ld      t0, 0(s5)                       # the object at the end of scratch
    li      t1, 24 + LC_UPDATE_ROOM
    bltu    t0, t1, 98f
    sub     t0, t0, t1
    sd      t0, 0(s5)
    add     s8, s5, t0
    ld      t0, NodeAction_arg(s2)
    li      t1, REQRESP_LIGHT_CLIENT_UPDATES_BY_RANGE
    beq     t0, t1, 10f
    li      a1, LC_OBJECT_FINALITY_UPDATE
    li      t1, REQRESP_LIGHT_CLIENT_FINALITY_UPDATE
    beq     t0, t1, 2f
    li      a1, LC_OBJECT_OPTIMISTIC_UPDATE
    li      t1, REQRESP_LIGHT_CLIENT_OPTIMISTIC_UPDATE
    beq     t0, t1, 2f
    li      t1, REQRESP_LIGHT_CLIENT_BOOTSTRAP
    bne     t0, t1, 96f
    beqz    s3, 96f                         # GetLightClientBootstrap: of the root's 32 bytes
    ld      t0, 16(s3)
    li      t1, 32
    bne     t0, t1, 96f
    li      a1, LC_OBJECT_BOOTSTRAP
    ld      t0, 8(s3)
    add     a2, s3, t0
    j       3f
2:  li      a2, 0
3:  mv      a0, s4
    mv      a3, s8
    mv      a4, s7
    mv      a5, s5
    mv      a6, s1
    call    node_lc_chunk
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 98f
    li      t0, LANTERN_NO_STATE_ANSWER
    bne     a0, t0, 4f
    li      t0, 24                          # none: ResourceUnavailable, no payload
    sd      t0, 16(sp)
    sd      t0, 24(sp)
    sd      zero, 32(sp)
    li      a0, 3
    addi    a1, sp, 16
    mv      a2, s5
    mv      a3, s7
    call    node_lc_error_chunk
    bnez    a0, 98f
    j       20f
4:  bnez    a0, 96f
    j       20f
10: beqz    s3, 96f                         # LightClientUpdatesByRange: start_period, count
    ld      t0, 16(s3)
    li      t1, 16
    bne     t0, t1, 96f
    ld      t0, 8(s3)
    add     t0, s3, t0
    ld      s9, 0(t0)
    ld      t1, 8(t0)
    li      t2, MAX_REQUEST_LIGHT_CLIENT_UPDATES
    bleu    t1, t2, 101f
    mv      t1, t2
101: add    s10, s9, t1
    bgeu    s10, s9, 102f
    li      s10, -1
102: sd     zero, 8(sp)
11: bgeu    s9, s10, 20f
    mv      a0, s4
    li      a1, LC_OBJECT_UPDATE
    mv      a2, s9
    mv      a3, s8
    mv      a4, s7
    mv      a5, s5
    mv      a6, s1
    call    node_lc_chunk
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 98f
    addi    s9, s9, 1
    beqz    a0, 12f
    ld      t0, 8(sp)                       # none: after an update, the end; before, the next period
    bnez    t0, 20f
    j       11b
12: li      t0, 1
    sd      t0, 8(sp)
    j       11b
20: ld      t0, 16(s7)                      # the event's size covers the chunks
    addi    t0, t0, NodeEvent_chunk + 24 + 7
    andi    t0, t0, -8
    sd      t0, 0(s6)
    addi    t0, t0, -NodeEvent_chunk
    sd      t0, 0(s7)
    ld      t0, 0(sp)
    sd      t0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 48
96: li      t0, LANTERN_INVALID_ENCODING
    sd      t0, NodeEvent_result(s6)
    ld      t0, 0(sp)
    sd      t0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 48
97: li      a0, LANTERN_INVALID_EVENT
    LEAVE 48
98: ld      t0, 0(sp)
    sd      t0, 0(s5)
    li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
END_FUNCTION node_run_lc_serve

# L2: (lc, kind, key, object, out, scratch, node) -> status: lantern_lc_read of the kind and key into
# the object, then its response chunk after the bytes of out: result 0, the context
# compute_fork_digest of the epoch of its attested slot. The statuses of lantern_lc_read and
# lantern_reqresp_write_chunk. The scratch's size as it came. s1 node, s2 the object, s3 out, s4
# scratch. Locals: 0 a ChunkHeader, 48 the fork, 56 the epoch, 64 the scratch's size.
LOCAL_FUNCTION node_lc_chunk
    ENTER 80
    mv      s2, a3
    mv      s3, a4
    mv      s4, a5
    mv      s1, a6
    ld      t0, 0(s4)
    sd      t0, 64(sp)
    li      t0, 24 + LC_UPDATE_ROOM
    sd      t0, 0(s2)
    addi    a4, sp, 48
    call    lantern_lc_read
    bnez    a0, 9f
    ld      t0, 8(s2)                       # attested_header.beacon.slot, a bootstrap's header.beacon.slot
    add     t0, s2, t0
    ld      t1, 48(sp)
    li      t2, FORK_CAPELLA
    bltu    t1, t2, 1f
    lwu     t1, 0(t0)
    add     t0, t0, t1
1:  ld      t0, 0(t0)
    li      t1, SLOTS_PER_EPOCH
    divu    t0, t0, t1
    sd      t0, 56(sp)
    li      t0, CHUNK_RESPONSE
    sd      t0, ChunkHeader_kind(sp)
    li      t0, 4
    sd      t0, ChunkHeader_context_length(sp)
    sd      zero, ChunkHeader_result(sp)
    sd      zero, ChunkHeader_context(sp)
    addi    a0, s1, Node_genesis_validators_root
    addi    a1, sp, 56
    addi    a2, s1, Node_config
    mv      a3, s4
    addi    a4, sp, ChunkHeader_context
    ld      t6, 48(sp)
    FORK_CALL compute_fork_digest
    bnez    a0, 8f
    ld      t0, 64(sp)                      # the scratch's size again (asm-standard: before each call)
    sd      t0, 0(s4)
    mv      a0, sp
    mv      a1, s2
    mv      a2, s4
    mv      a3, s3
    call    lantern_reqresp_write_chunk
9:  ld      t0, 64(sp)                      # the scratch's size, as it came
    sd      t0, 0(s4)
    LEAVE 80
8:  li      a0, LANTERN_INVALID_ENCODING
    j       9b
END_FUNCTION node_lc_chunk

# L1: (result, payload, scratch, out) -> status: a response chunk of the result, with no context bytes, after the bytes of out. Locals: 0 a ChunkHeader.
LOCAL_FUNCTION node_lc_error_chunk
    FRAME 48
    li      t0, CHUNK_RESPONSE
    sd      t0, ChunkHeader_kind(sp)
    sd      zero, ChunkHeader_context_length(sp)
    sd      a0, ChunkHeader_result(sp)
    sd      zero, ChunkHeader_context(sp)
    mv      a0, sp
    call    lantern_reqresp_write_chunk
    UNFRAME 48
END_FUNCTION node_lc_error_chunk

# L1: a light client request of the stream entry a0 (node.md): its a2 bytes at a1 (none with 0) to a
# new id, a NODE_WORK_LC_SERVE of them with the light client store as state_c; the stream takes
# NODE_STREAM_SERVING, its list empty. s3 the entry, s4 the id. Locals: 0 a ByteList of the bytes.
LOCAL_FUNCTION node_lc_request
    ENTER 64
    mv      s3, a0
    li      s4, 0
    beqz    a2, 1f
    addi    t0, a2, 24
    sd      t0, 0(sp)
    li      t0, 24
    sd      t0, 8(sp)
    sd      a2, 16(sp)
    addi    a0, sp, 24
    call    lantern_copy
    mv      a0, sp
    call    node_put
    mv      s4, a0
1:  li      a0, NODE_WORK_LC_SERVE
    li      a1, 0
    li      a2, 0
    mv      a3, s4
    ld      a4, NodeStream_handle(s3)
    ld      a5, NodeStream_method(s3)
    call    node_work
    li      t0, NODE_LC_ID
    sd      t0, NodeAction_state_c(a0)
    li      t0, NODE_STREAM_SERVING
    sd      t0, NodeStream_state(s3)
    sd      zero, (NodeStream_list + 16)(s3)
    LEAVE 64
END_FUNCTION node_lc_request

# L1: the NODE_EV_WORK_DONE s3 of a NODE_WORK_LC_SERVE (node.md): its bytes go, then the chunks to
# the stream in a STREAM_WRITE and a STREAM_CLOSE, or a STREAM_RESET; then the stream goes. s1 the
# node, s6 the actions; s4 the stream, s5 the chunks' bytes, s7 the event's size.
LOCAL_FUNCTION node_lc_served
    ENTER 0
    ld      a1, NodeAction_data(s3)
    beqz    a1, 1f
    li      a0, NODE_ACT_BYTES_FREE
    li      a2, 0
    call    node_ids
1:  ld      a0, NodeAction_target(s3)
    call    node_find_stream
    li      t0, -1
    beq     a0, t0, 9f
    mv      s4, a1
    ld      t0, NodeEvent_result(s3)
    bnez    t0, 8f
    ld      s5, (NodeEvent_chunk + 16)(s3)
    beqz    s5, 7f
    addi    s7, s5, 32 + 7
    andi    s7, s7, -8
    mv      a0, s7
    call    node_out
    beqz    a0, 8f
    sd      s7, 0(a0)
    li      t0, LIBP2P_EVENT_STREAM_WRITE
    sd      t0, 8(a0)
    ld      t0, NodeStream_handle(s4)
    sd      t0, 16(a0)
    sd      s5, 24(a0)
    addi    a0, a0, 32
    addi    a1, s3, NodeEvent_chunk + 24
    mv      a2, s5
    call    lantern_copy
7:  li      a0, LIBP2P_EVENT_STREAM_CLOSE
    ld      a1, NodeStream_handle(s4)
    call    node_out_handle
    mv      a0, s4
    call    node_drop_stream
9:  LEAVE 0
8:  li      a0, LIBP2P_EVENT_STREAM_RESET
    ld      a1, NodeStream_handle(s4)
    call    node_out_handle
    mv      a0, s4
    call    node_drop_stream
    LEAVE 0
END_FUNCTION node_lc_served

# L1: (lc, event) -> a0: the latest update's fields of a light client work at NodeEvent_index and
# NodeEvent_root (node.md, NODE_WORK_LC_HEAD): its finalized slot; its attested slot, its
# supermajority, 1, its signature slot. 1, or 0 with no latest update. s1 lc, s2 event, s3 the
# update.
LOCAL_FUNCTION node_lc_slots
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    li      a0, 0
    ld      a2, LcStore_latest(s1)
    beqz    a2, 9f
    mv      a0, s1
    li      a1, LC_PART_UPDATES
    call    lc_ref
    mv      s3, a0
    mv      a0, s1
    li      a1, LC_PART_HEADERS
    ld      a2, LcUpdate_finalized_header(s3)
    call    lc_ref
    addi    a0, a0, LcHeader_header
    ld      t0, 8(a0)
    add     t0, a0, t0
    ld      t0, 0(t0)
    sd      t0, NodeEvent_index(s2)
    mv      a0, s1
    li      a1, LC_PART_HEADERS
    ld      a2, LcUpdate_attested_header(s3)
    call    lc_ref
    addi    a0, a0, LcHeader_header
    ld      t0, 8(a0)
    add     t0, a0, t0
    ld      t0, 0(t0)
    sd      t0, NodeEvent_root(s2)
    addi    a0, s3, LcUpdate_sync_aggregate
    call    lc_participants
    li      t0, 3
    mul     a0, a0, t0
    li      t0, SYNC_COMMITTEE_SIZE * 2
    sltu    t1, a0, t0
    xori    t1, t1, 1
    sd      t1, (NodeEvent_root + 8)(s2)
    li      t0, 1
    sd      t0, (NodeEvent_root + 16)(s2)
    ld      t0, LcUpdate_signature_slot(s3)
    sd      t0, (NodeEvent_root + 24)(s2)
    li      a0, 1
9:  LEAVE 0
END_FUNCTION node_lc_slots

# L2: (node, work, data, lc, scratch, event, room) -> status: a NODE_WORK_LC_PUBLISH or
# NODE_WORK_LC_GOSSIP of lantern_node_run (node.md): the latest update of the topic arg, as a
# ByteList at NodeEvent_chunk of the event (PUBLISH) or at the end of scratch (GOSSIP, matched
# against data), its fields, and the result. s1 node, s2 work, s3 data, s4 lc, s5 scratch, s6
# event, s7 the object, s8 the kind, s9 1 for a publish. Locals: 0 the scratch's size, 8 the fork,
# 16 the epoch, 24 a ForkDigest.
LOCAL_FUNCTION node_run_lc_gossip
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    ld      t0, 0(s5)
    sd      t0, 0(sp)
    ld      t0, NodeAction_work_kind(s2)
    addi    t0, t0, -NODE_WORK_LC_PUBLISH
    seqz    s9, t0
    ld      t0, NodeAction_arg(s2)
    li      s8, LC_OBJECT_FINALITY_UPDATE
    li      t1, GOSSIP_LIGHT_CLIENT_FINALITY_UPDATE
    beq     t0, t1, 1f
    li      s8, LC_OBJECT_OPTIMISTIC_UPDATE
    li      t1, GOSSIP_LIGHT_CLIENT_OPTIMISTIC_UPDATE
    bne     t0, t1, 97f
1:  beqz    s4, 97f
    beqz    s9, 2f
    addi    t0, a6, -NodeEvent_chunk        # PUBLISH: the object in the event
    andi    t0, t0, -8
    li      t1, 64
    bltu    t0, t1, 98f
    addi    s7, s6, NodeEvent_chunk
    sd      t0, 0(s7)
    j       3f
2:  ld      t0, 0(s5)                       # GOSSIP: at the end of scratch; no room, IGNORE
    li      t1, 24 + LC_UPDATE_ROOM
    bltu    t0, t1, 96f
    sub     t0, t0, t1
    sd      t0, 0(s5)
    add     s7, s5, t0
    sd      t1, 0(s7)
3:  mv      a0, s4
    mv      a1, s8
    li      a2, 0
    mv      a3, s7
    addi    a4, sp, 8
    call    lantern_lc_read
    li      t0, LANTERN_BUFFER_TOO_SMALL
    bne     a0, t0, 4f
    bnez    s9, 98f
    j       96f
4:  bnez    a0, 96f
    ld      t0, 8(s7)                       # the ForkDigest of the epoch of attested_header.beacon.slot: fork_digest
    add     t0, s7, t0
    ld      t1, 8(sp)
    li      t2, FORK_CAPELLA
    bltu    t1, t2, 5f
    lwu     t1, 0(t0)
    add     t0, t0, t1
5:  ld      t0, 0(t0)
    li      t1, SLOTS_PER_EPOCH
    divu    t0, t0, t1
    sd      t0, 16(sp)
    sd      zero, 24(sp)
    addi    a0, s1, Node_genesis_validators_root
    addi    a1, sp, 16
    addi    a2, s1, Node_config
    mv      a3, s5
    addi    a4, sp, 24
    ld      t6, 8(sp)
    FORK_CALL compute_fork_digest
    bnez    a0, 96f
    lwu     t0, 24(sp)
    lwu     t1, Node_fork_digest(s1)
    bne     t0, t1, 96f
    bnez    s9, 7f
    beqz    s3, 96f                         # GOSSIP: data must be its bytes
    ld      t2, 16(s3)
    ld      t0, 16(s7)
    bne     t2, t0, 96f
    ld      a0, 8(s3)
    add     a0, s3, a0
    ld      a1, 8(s7)
    add     a1, s7, a1
6:  beqz    t2, 7f
    lbu     t0, 0(a0)
    lbu     t1, 0(a1)
    bne     t0, t1, 96f
    addi    a0, a0, 1
    addi    a1, a1, 1
    addi    t2, t2, -1
    j       6b
7:  mv      a0, s4                          # the latest update's fields
    mv      a1, s6
    call    node_lc_slots
    beqz    a0, 96f
    beqz    s9, 8f
    ld      t0, 8(s7)                       # PUBLISH: the event's size covers the bytes
    ld      t1, 16(s7)
    add     t0, t0, t1
    addi    t0, t0, NodeEvent_chunk + 7
    andi    t0, t0, -8
    sd      t0, 0(s6)
    addi    t0, t0, -NodeEvent_chunk
    sd      t0, 0(s7)
8:  sd      zero, NodeEvent_result(s6)      # LANTERN_VALID
    ld      t0, 0(sp)
    sd      t0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 32
96: li      t0, LANTERN_GOSSIP_IGNORE
    sd      t0, NodeEvent_result(s6)
    ld      t0, 0(sp)
    sd      t0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 32
97: ld      t0, 0(sp)
    sd      t0, 0(s5)
    li      a0, LANTERN_INVALID_EVENT
    LEAVE 32
98: ld      t0, 0(sp)
    sd      t0, 0(s5)
    li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION node_run_lc_gossip
