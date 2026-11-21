/*
 * The light client data of the node, ARM64: in the common object. Requirements: docs/reference/node.md,
 * beacon-api.md and light-client.md.
 */

/*
 * L2: (route, connection, flags) -> x0: a light client read of NODE_EV_API (node.md): a
 * NODE_WORK_API_ENCODE with the light client store as state_c; 0. The node x19, the actions x24.
 * x21 the route, x22 the connection, x23 the answer flags, x25 the operation, x26 the bytes' id.
 * Locals: L a ByteList of the bytes put.
 */
LOCAL_FUNCTION node_api_lc
    ENTER 64
    mov     x21, x0
    mov     x22, x1
    mov     x23, x2
    ldr     x9, [x21, #ApiRoute_response]
    cmp     x9, #API_TYPE_SSZ
    b.ne    1f
    orr     x23, x23, #API_ANSWER_SSZ
1:  ldr     x25, [x21, #ApiRoute_op]
    mov     x26, #0
    cmp     x25, #API_OP_GET_LIGHT_CLIENT_BOOTSTRAP
    b.ne    2f
    add     x9, sp, #L                      /* getLightClientBootstrap: the root's 32 bytes */
    mov     x10, #56
    mov     x11, #24
    stp     x10, x11, [x9]
    mov     x10, #32
    str     x10, [x9, #16]
    add     x0, x9, #24
    add     x1, x21, #ApiRoute_id_root
    bl      lantern_copy_root
    b       3f
2:  cmp     x25, #API_OP_GET_LIGHT_CLIENT_UPDATES_BY_RANGE
    b.ne    4f
    ldr     x9, [x21, #ApiRoute_start_period]   /* the periods: start, and past the last */
    ldr     x10, [x21, #ApiRoute_count]
    mov     x11, #MAX_REQUEST_LIGHT_CLIENT_UPDATES
    cmp     x10, x11
    csel    x10, x11, x10, hi
    adds    x10, x9, x10
    csinv   x10, x10, xzr, cc
    add     x11, sp, #L
    mov     x12, #40
    mov     x13, #24
    stp     x12, x13, [x11]
    mov     x12, #16
    str     x12, [x11, #16]
    stp     x9, x10, [x11, #24]
3:  add     x0, sp, #L
    bl      node_put
    mov     x26, x0
4:  mov     x0, #NODE_WORK_API_ENCODE
    mov     x1, #0
    mov     x2, #0
    mov     x3, x26
    mov     x4, x22
    orr     x5, x25, x23, lsl #8
    bl      node_work
    mov     x9, #NODE_LC_ID
    str     x9, [x0, #NodeAction_state_c]
    mov     x0, #0
    LEAVE 64
END_FUNCTION node_api_lc

/*
 * L2: (lc, work, data, scratch, view) -> status, the node x19: the light client read of a NODE_WORK_API_ENCODE
 * (node.md) into the view: for getLightClientUpdatesByRange its store, periods, JSON room and
 * cursor, which its body reads; else the object's SSZ bytes (ApiView_lc_bytes), its fork, and as
 * JSON its JSON (ApiView_lc_json). With none, ApiView_status 404; a fault of the JSON, 500.
 * LANTERN_INVALID_EVENT without the store or the work's bytes; LANTERN_BUFFER_TOO_SMALL with too
 * little scratch. x19 lc, x20 work, x21 data, x22 scratch, x23 view, x24 the kind, x25 the object,
 * x26 the JSON, x27 the cursor, x28 1 for SSZ. Locals: L the fork.
 */
LOCAL_FUNCTION node_api_lc_read
    ENTER 16
    mov     x12, x19                        /* the node */
    str     x12, [sp, #(L + 8)]
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    cbz     x19, 97f
    ldr     x9, [x20, #NodeAction_arg]
    ubfx    x10, x9, #8, #8
    tst     x10, #API_ANSWER_SSZ
    cset    x28, ne
    and     x9, x9, #255
    mov     x24, #LC_OBJECT_FINALITY_UPDATE
    cmp     x9, #API_OP_GET_LIGHT_CLIENT_FINALITY_UPDATE
    b.eq    2f
    mov     x24, #LC_OBJECT_OPTIMISTIC_UPDATE
    cmp     x9, #API_OP_GET_LIGHT_CLIENT_OPTIMISTIC_UPDATE
    b.eq    2f
    mov     x24, #LC_OBJECT_UPDATE
    mov     x11, #16
    cmp     x9, #API_OP_GET_LIGHT_CLIENT_UPDATES_BY_RANGE
    b.eq    1f
    mov     x24, #LC_OBJECT_BOOTSTRAP
    mov     x11, #32
1:  cbz     x21, 97f                        /* the root, or the two periods */
    ldr     x9, [x21, #16]
    cmp     x9, x11
    b.ne    97f
2:  ldr     x9, [x22]                       /* the object at the end of scratch */
    MOVQ    x10, 24 + LC_UPDATE_ROOM
    subs    x9, x9, x10
    b.lo    98f
    str     x9, [x22]
    add     x25, x22, x9
    str     x10, [x25]
    STQ     x25, x23, ApiView_lc_bytes
    STQ     xzr, x23, ApiView_lc_json
    ldr     x9, [x22]                       /* its JSON's room, and a cursor */
    MOVQ    x10, 24 + 4 * LC_UPDATE_ROOM + 4096 + JSON_CURSOR_SIZE
    subs    x9, x9, x10
    b.lo    98f
    str     x9, [x22]
    add     x26, x22, x9
    MOVQ    x10, 24 + 4 * LC_UPDATE_ROOM + 4096
    mov     x11, #24
    stp     x10, x11, [x26]
    str     xzr, [x26, #16]
    add     x27, x26, x10
    cmp     x24, #LC_OBJECT_UPDATE
    b.ne    3f
    STQ     x19, x23, ApiView_lc_store      /* getLightClientUpdatesByRange: its body reads them */
    STQ     x27, x23, ApiView_lc_cursor
    STQ     x26, x23, ApiView_lc_json
    STQ     x28, x23, ApiView_lc_ssz
    ldr     x9, [x21, #8]                   /* the periods, and the node for the context bytes */
    add     x9, x21, x9
    ldp     x10, x11, [x9]
    ldr     x12, [sp, #(L + 8)]
    STQ     x10, x23, ApiView_lc_start
    STQ     x11, x23, ApiView_lc_end
    STQ     x12, x23, ApiView_node
    mov     x0, #LANTERN_OK
    LEAVE 16
3:  mov     x0, x19
    mov     x1, x24
    mov     x2, #0
    cbnz    x24, 31f
    ldr     x9, [x21, #8]                   /* the bootstrap: of the root */
    add     x2, x21, x9
31: mov     x3, x25
    add     x4, sp, #L
    bl      lantern_lc_read
    cmp     x0, #LANTERN_NO_STATE_ANSWER
    b.eq    80f
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    98f
    cbnz    x0, 81f
    ldr     x9, [sp, #L]
    str     x9, [x23, #ApiView_fork]
    cbnz    x28, 9f
    mov     x0, x27
    mov     x1, #JSON_CURSOR_SIZE
    bl      lantern_zero
    mov     x0, #NODE_JSON_LC_BOOTSTRAP     /* the JSON of the kind */
    cmp     x24, #LC_OBJECT_FINALITY_UPDATE
    mov     x9, #NODE_JSON_LC_FINALITY_UPDATE
    csel    x0, x9, x0, eq
    cmp     x24, #LC_OBJECT_OPTIMISTIC_UPDATE
    mov     x9, #NODE_JSON_LC_OPTIMISTIC_UPDATE
    csel    x0, x9, x0, eq
    mov     x1, x25
    mov     x2, x27
    mov     x3, x26
    ldr     x15, [sp, #L]
    FORK_CALL node_json
    cmp     x0, #LANTERN_JSON_MORE
    b.eq    98f
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    98f
    cbnz    x0, 81f
    STQ     x26, x23, ApiView_lc_json
9:  mov     x0, #LANTERN_OK
    LEAVE 16
80: mov     x9, #404
    str     x9, [x23, #ApiView_status]
    mov     x0, #LANTERN_OK
    LEAVE 16
81: mov     x9, #500
    str     x9, [x23, #ApiView_status]
    mov     x0, #LANTERN_OK
    LEAVE 16
97: mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 16
98: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION node_api_lc_read

/*
 * L2: the body of getLightClientUpdatesByRange (beacon-api.md) of the view x22 (its node ApiView_node), with
 * the writer of api_put: from the first period with an update, each update to the first period of
 * none. Locals: 16 the fork, 24 1 once an update is in, 32 the period, 40 a chunk's length, 48 an
 * epoch, 56 a digest.
 */
LOCAL_FUNCTION api_lc_updates_body
    FRAME 48
    stp     xzr, xzr, [sp, #16]
    LDQ     x9, x22, ApiView_lc_start
    str     x9, [sp, #32]
    LDQ     x9, x22, ApiView_lc_ssz
    cbnz    x9, 1f
    API_LIT api_lc_open
1:  ldr     x9, [sp, #32]
    LDQ     x10, x22, ApiView_lc_end
    cmp     x9, x10
    b.hs    8f
    LDQ     x0, x22, ApiView_lc_store
    mov     x1, #LC_OBJECT_UPDATE
    ldr     x2, [sp, #32]
    LDQ     x3, x22, ApiView_lc_bytes
    MOVQ    x9, 24 + LC_UPDATE_ROOM
    str     x9, [x3]
    add     x4, sp, #16
    bl      lantern_lc_read
    cbz     x0, 2f
    ldr     x9, [sp, #24]                   /* none: after an update, the end; before, the next period */
    cbnz    x9, 8f
    ldr     x9, [sp, #32]
    add     x9, x9, #1
    str     x9, [sp, #32]
    b       1b
2:  LDQ     x9, x22, ApiView_lc_ssz
    cbz     x9, 3f
    LDQ     x9, x22, ApiView_lc_bytes       /* SSZ: response_chunk_len, the context, the bytes */
    ldr     x10, [x9, #16]
    add     x10, x10, #4
    str     x10, [sp, #40]
    add     x0, sp, #40
    mov     x1, #8
    bl      api_put
    LDQ     x9, x22, ApiView_lc_bytes
    ldr     x10, [x9, #8]
    add     x10, x9, x10
    ldr     x11, [sp, #16]
    cmp     x11, #FORK_CAPELLA
    b.lo    21f
    ldr     w12, [x10]
    add     x10, x10, x12
21: ldr     x9, [x10]                       /* attested_header.beacon.slot: its epoch's fork digest */
    mov     x10, #SLOTS_PER_EPOCH
    udiv    x9, x9, x10
    str     x9, [sp, #48]
    LDQ     x3, x22, ApiView_lc_json        /* its room, as the digest's scratch */
    MOVQ    x9, 24 + 4 * LC_UPDATE_ROOM + 4096
    str     x9, [x3]
    LDQ     x9, x22, ApiView_node
    add     x0, x9, #Node_genesis_validators_root
    add     x1, sp, #48
    add     x2, x9, #Node_config
    add     x4, sp, #56
    ldr     x15, [sp, #16]
    FORK_CALL compute_fork_digest
    add     x0, sp, #56
    mov     x1, #4
    bl      api_put
    LDQ     x9, x22, ApiView_lc_bytes
    ldr     x10, [x9, #8]
    add     x0, x9, x10
    ldr     x1, [x9, #16]
    bl      api_put
    b       4f
3:  ldr     x9, [sp, #24]                   /* JSON: {"version":…,"data":…}, with , between */
    cbz     x9, 31f
    API_LIT api_lc_comma
31: API_LIT api_j_version
    ldr     x0, [sp, #16]
    bl      api_fork_name
    API_LIT api_g_data
    LDQ     x9, x22, ApiView_lc_json
    MOVQ    x10, 24 + 4 * LC_UPDATE_ROOM + 4096
    mov     x11, #24
    stp     x10, x11, [x9]
    str     xzr, [x9, #16]
    LDQ     x0, x22, ApiView_lc_cursor
    mov     x1, #JSON_CURSOR_SIZE
    bl      lantern_zero
    mov     x0, #NODE_JSON_LC_UPDATE
    LDQ     x1, x22, ApiView_lc_bytes
    LDQ     x2, x22, ApiView_lc_cursor
    LDQ     x3, x22, ApiView_lc_json
    ldr     x15, [sp, #16]
    FORK_CALL node_json
    cbnz    x0, 8f
    LDQ     x9, x22, ApiView_lc_json
    ldr     x10, [x9, #8]
    add     x0, x9, x10
    ldr     x1, [x9, #16]
    bl      api_put
    API_LIT api_end1
4:  mov     x9, #1
    str     x9, [sp, #24]
    ldr     x9, [sp, #32]
    add     x9, x9, #1
    str     x9, [sp, #32]
    b       1b
8:  LDQ     x9, x22, ApiView_lc_ssz
    cbnz    x9, 9f
    API_LIT api_lc_close
9:  UNFRAME 48
END_FUNCTION api_lc_updates_body

/*
 * L2: (node, store, work, state_a, data, state_c, scratch, event) -> status: a NODE_WORK_LC_BLOCK or
 * NODE_WORK_LC_HEAD of lantern_node_run (node.md). x19 node, x20 store, x21 work, x22 state_a, x23
 * data, x24 the LcStore, x25 scratch, x26 event, x27 the latest update.
 */
LOCAL_FUNCTION node_run_lc
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    mov     x25, x6
    mov     x26, x7
    cbz     x24, 97f
    ldr     x9, [x21, #NodeAction_work_kind]
    cmp     x9, #NODE_WORK_LC_SERVE         /* LC_SERVE: the answer of a light client method; x8 the event's room */
    b.ne    1f
    mov     x0, x19
    mov     x1, x21
    mov     x2, x23
    mov     x3, x24
    mov     x4, x25
    mov     x5, x26
    mov     x6, x8
    bl      node_run_lc_serve
    LEAVE 0
1:  cmp     x9, #NODE_WORK_LC_HEAD
    b.eq    2f
    cbz     x22, 97f                        /* LC_BLOCK: lantern_lc_on_block of the post-state and the block */
    cbz     x23, 97f
    mov     x0, x24
    add     x1, x19, #Node_config
    mov     x2, x22
    mov     x3, x23
    mov     x4, #0
    mov     x5, x25
    bl      lantern_lc_on_block
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    9f
    str     x0, [x26, #NodeEvent_result]
    mov     x0, #LANTERN_OK
    LEAVE 0
2:  mov     x0, x24                         /* LC_HEAD: lantern_lc_on_head of the head and the store's finalized checkpoint */
    add     x1, x19, #Node_config
    add     x2, x19, #Node_head_root
    add     x3, x20, #Store_finalized_checkpoint
    mov     x4, x25
    bl      lantern_lc_on_head
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    9f
    str     x0, [x26, #NodeEvent_result]
    cbnz    x0, 8f
    ldr     x2, [x24, #LcStore_latest]      /* the latest finality update's slots and supermajority */
    cbz     x2, 8f
    mov     x0, x24
    mov     x1, #LC_PART_UPDATES
    bl      lc_ref
    mov     x27, x0
    mov     x0, x24
    mov     x1, #LC_PART_HEADERS
    ldr     x2, [x27, #LcUpdate_finalized_header]
    bl      lc_ref
    add     x0, x0, #LcHeader_header
    ldr     x9, [x0, #8]
    ldr     x9, [x0, x9]
    str     x9, [x26, #NodeEvent_index]
    mov     x0, x24
    mov     x1, #LC_PART_HEADERS
    ldr     x2, [x27, #LcUpdate_attested_header]
    bl      lc_ref
    add     x0, x0, #LcHeader_header
    ldr     x9, [x0, #8]
    ldr     x9, [x0, x9]
    str     x9, [x26, #NodeEvent_root]
    add     x0, x27, #LcUpdate_sync_aggregate
    bl      lc_participants
    mov     x9, #3
    mul     x0, x0, x9
    mov     x9, #(SYNC_COMMITTEE_SIZE * 2)
    cmp     x0, x9
    cset    x9, hs
    mov     x10, #1
    stp     x9, x10, [x26, #(NodeEvent_root + 8)]
8:  mov     x0, #LANTERN_OK
    LEAVE 0
9:  LEAVE 0
97: mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 0
END_FUNCTION node_run_lc

/*
 * L1: the NODE_EV_WORK_DONE x21 of a NODE_WORK_LC_HEAD (node.md, The events): a new finality update,
 * or a new optimistic update, sets the node's fields and gives the event of its topic. x19 the node,
 * x24 the actions; x25 its finalized slot, x26 its attested slot, x27 its supermajority.
 */
LOCAL_FUNCTION node_lc_head_done
    ENTER 0
    ldr     x9, [x21, #NodeEvent_result]
    cbnz    x9, 9f
    ldr     x9, [x21, #(NodeEvent_root + 16)]
    cbz     x9, 9f
    ldr     x25, [x21, #NodeEvent_index]
    ldr     x26, [x21, #NodeEvent_root]
    ldr     x27, [x21, #(NodeEvent_root + 8)]
    LDQ     x9, x19, Node_lc_finality_slot  /* finality: a higher finalized slot, or the same with a new supermajority */
    cmp     x25, x9
    b.hi    1f
    b.ne    2f
    LDQ     x10, x19, Node_lc_finality_super
    cbnz    x10, 2f
    cbz     x27, 2f
1:  STQ     x25, x19, Node_lc_finality_slot
    STQ     x27, x19, Node_lc_finality_super
    mov     x0, #API_TOPIC_LIGHT_CLIENT_FINALITY_UPDATE
    mov     x1, #API_TOPIC_LIGHT_CLIENT_FINALITY_UPDATE
    bl      node_lc_event
2:  LDQ     x9, x19, Node_lc_optimistic_slot   /* optimistic: a higher attested slot */
    cmp     x26, x9
    b.ls    9f
    STQ     x26, x19, Node_lc_optimistic_slot
    mov     x0, #API_TOPIC_LIGHT_CLIENT_OPTIMISTIC_UPDATE
    mov     x1, #API_TOPIC_LIGHT_CLIENT_OPTIMISTIC_UPDATE
    bl      node_lc_event
9:  LEAVE 0
END_FUNCTION node_lc_head_done

/* L1: a NODE_WORK_API_EVENT of the topic x0 (arg x1) with the light client store as state_c, when an entry has the topic. */
LOCAL_FUNCTION node_lc_event
    FRAME 16
    str     x1, [sp, #16]
    bl      node_api_subscribed
    cbz     x0, 9f
    mov     x0, #NODE_WORK_API_EVENT
    mov     x1, #0
    mov     x2, #0
    mov     x3, #0
    mov     x4, #0
    ldr     x5, [sp, #16]
    bl      node_work
    mov     x9, #NODE_LC_ID
    str     x9, [x0, #NodeAction_state_c]
9:  UNFRAME 16
END_FUNCTION node_lc_event

/*
 * L2: (out, topic, lc, scratch) -> x0: the text of a light client event (beacon-api.md, eventstream):
 * event: <topic> LF data: {"version":…,"data":…} LF LF, into the ByteList out, its count set;
 * LANTERN_OK, LANTERN_NO_STATE_ANSWER with no update, LANTERN_BUFFER_TOO_SMALL. The writer's
 * registers; x19 the topic, x20 lc, x21 scratch, x22 the object, x23 out, x28 the kind. Locals: L
 * the fork, L + 8 the scratch's size.
 */
LOCAL_FUNCTION api_lc_event_text
    ENTER 16
    mov     x23, x0
    mov     x19, x1
    mov     x20, x2
    mov     x21, x3
    ldr     x9, [x21]
    str     x9, [sp, #(L + 8)]
    MOVQ    x10, 24 + LC_UPDATE_ROOM + JSON_CURSOR_SIZE  /* the object and a cursor at the end of scratch */
    subs    x9, x9, x10
    b.lo    98f
    str     x9, [x21]
    add     x22, x21, x9
    MOVQ    x10, 24 + LC_UPDATE_ROOM
    str     x10, [x22]
    mov     x28, #LC_OBJECT_FINALITY_UPDATE
    cmp     x19, #API_TOPIC_LIGHT_CLIENT_FINALITY_UPDATE
    mov     x9, #LC_OBJECT_OPTIMISTIC_UPDATE
    csel    x28, x28, x9, eq
    mov     x0, x20
    mov     x1, x28
    mov     x2, #0
    mov     x3, x22
    add     x4, sp, #L
    bl      lantern_lc_read
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    98f
    cbnz    x0, 9f
    mov     x25, #1                         /* the writer */
    mov     x27, #0
    add     x24, x23, #24
    ldr     x9, [x23]
    add     x26, x23, x9
    API_LIT api_ev_event
    cmp     x19, #API_TOPIC_LIGHT_CLIENT_FINALITY_UPDATE
    b.ne    1f
    API_LIT api_ev_t_lc_finality
    b       2f
1:  API_LIT api_ev_t_lc_optimistic
2:  API_LIT api_ev_data
    API_LIT api_j_version
    ldr     x0, [sp, #L]
    bl      api_fork_name
    API_LIT api_g_data
    cbnz    x27, 98f
    add     x9, x23, #24                    /* the JSON after the bytes so far */
    sub     x9, x24, x9
    mov     x10, #24
    stp     x10, x9, [x23, #8]
    MOVQ    x2, 24 + LC_UPDATE_ROOM
    add     x2, x22, x2
    mov     x0, x2
    mov     x1, #JSON_CURSOR_SIZE
    bl      lantern_zero
    mov     x0, #NODE_JSON_LC_FINALITY_UPDATE
    cmp     x28, #LC_OBJECT_FINALITY_UPDATE
    mov     x9, #NODE_JSON_LC_OPTIMISTIC_UPDATE
    csel    x0, x0, x9, eq
    mov     x1, x22
    MOVQ    x2, 24 + LC_UPDATE_ROOM
    add     x2, x22, x2
    mov     x3, x23
    ldr     x15, [sp, #L]
    FORK_CALL node_json
    cmp     x0, #LANTERN_JSON_MORE
    b.eq    98f
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    98f
    cbnz    x0, 97f
    ldr     x9, [x23, #16]
    add     x24, x23, #24
    add     x24, x24, x9
    API_LIT api_end1
    API_LIT api_ev_lf2
    cbnz    x27, 98f
    add     x9, x23, #24
    sub     x9, x24, x9
    mov     x10, #24
    stp     x10, x9, [x23, #8]
    mov     x0, #LANTERN_OK
9:  ldr     x9, [sp, #(L + 8)]
    str     x9, [x21]
    LEAVE 16
97: mov     x0, #LANTERN_INVALID_ENCODING
    b       9b
98: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    b       9b
END_FUNCTION api_lc_event_text

/*
 * L2: (node, work, data, lc, scratch, event, room) -> status: a NODE_WORK_LC_SERVE of
 * lantern_node_run (node.md): the response chunks of the light client method arg at
 * NodeEvent_chunk of the event. x19 node, x20 work, x21 data, x22 lc, x23 scratch, x24 event, x25
 * the chunks' ByteList, x26 the object at the end of scratch, x27 the period, x28 the end period.
 * Locals: L the scratch's size, L + 8 1 once an update is in, L + 16 an empty ByteList.
 */
LOCAL_FUNCTION node_run_lc_serve
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    ldr     x9, [x23]
    str     x9, [sp, #L]
    sub     x9, x6, #NodeEvent_chunk        /* the chunks, in the event */
    and     x9, x9, #~7
    cmp     x9, #64
    b.lo    98f
    add     x25, x24, #NodeEvent_chunk
    mov     x10, #24
    stp     x9, x10, [x25]
    str     xzr, [x25, #16]
    ldr     x9, [x23]                       /* the object at the end of scratch */
    MOVQ    x10, 24 + LC_UPDATE_ROOM
    subs    x9, x9, x10
    b.lo    98f
    str     x9, [x23]
    add     x26, x23, x9
    ldr     x9, [x20, #NodeAction_arg]
    cmp     x9, #REQRESP_LIGHT_CLIENT_UPDATES_BY_RANGE
    b.eq    10f
    mov     x1, #LC_OBJECT_FINALITY_UPDATE
    cmp     x9, #REQRESP_LIGHT_CLIENT_FINALITY_UPDATE
    b.eq    2f
    mov     x1, #LC_OBJECT_OPTIMISTIC_UPDATE
    cmp     x9, #REQRESP_LIGHT_CLIENT_OPTIMISTIC_UPDATE
    b.eq    2f
    cmp     x9, #REQRESP_LIGHT_CLIENT_BOOTSTRAP
    b.ne    96f
    cbz     x21, 96f                        /* GetLightClientBootstrap: of the root's 32 bytes */
    ldr     x9, [x21, #16]
    cmp     x9, #32
    b.ne    96f
    mov     x1, #LC_OBJECT_BOOTSTRAP
    ldr     x9, [x21, #8]
    add     x2, x21, x9
    b       3f
2:  mov     x2, #0
3:  mov     x0, x22
    mov     x3, x26
    mov     x4, x25
    mov     x5, x23
    mov     x6, x19
    bl      node_lc_chunk
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    98f
    cmp     x0, #LANTERN_NO_STATE_ANSWER
    b.ne    4f
    mov     x9, #24                         /* none: ResourceUnavailable, no payload */
    mov     x10, #24
    stp     x9, x10, [sp, #(L + 16)]
    str     xzr, [sp, #(L + 32)]
    mov     x0, #3
    add     x1, sp, #(L + 16)
    mov     x2, x23
    mov     x3, x25
    bl      node_lc_error_chunk
    cbnz    x0, 98f
    b       20f
4:  cbnz    x0, 96f
    b       20f
10: cbz     x21, 96f                        /* LightClientUpdatesByRange: start_period, count */
    ldr     x9, [x21, #16]
    cmp     x9, #16
    b.ne    96f
    ldr     x9, [x21, #8]
    add     x9, x21, x9
    ldp     x27, x10, [x9]
    mov     x11, #MAX_REQUEST_LIGHT_CLIENT_UPDATES
    cmp     x10, x11
    csel    x10, x11, x10, hi
    adds    x28, x27, x10
    csinv   x28, x28, xzr, cc
    str     xzr, [sp, #(L + 8)]
11: cmp     x27, x28
    b.hs    20f
    mov     x0, x22
    mov     x1, #LC_OBJECT_UPDATE
    mov     x2, x27
    mov     x3, x26
    mov     x4, x25
    mov     x5, x23
    mov     x6, x19
    bl      node_lc_chunk
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    98f
    cbz     x0, 12f
    ldr     x9, [sp, #(L + 8)]              /* none: after an update, the end; before, the next period */
    cbnz    x9, 20f
    add     x27, x27, #1
    b       11b
12: mov     x9, #1
    str     x9, [sp, #(L + 8)]
    add     x27, x27, #1
    b       11b
20: ldr     x9, [x25, #16]                  /* the event's size covers the chunks */
    add     x9, x9, #(NodeEvent_chunk + 24 + 7)
    and     x9, x9, #~7
    str     x9, [x24]
    sub     x9, x9, #NodeEvent_chunk
    str     x9, [x25]
    ldr     x9, [sp, #L]
    str     x9, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 48
96: mov     x9, #LANTERN_INVALID_ENCODING
    str     x9, [x24, #NodeEvent_result]
    ldr     x9, [sp, #L]
    str     x9, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 48
98: ldr     x9, [sp, #L]
    str     x9, [x23]
    mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
END_FUNCTION node_run_lc_serve

/*
 * L2: (lc, kind, key, object, out, scratch, node) -> status: lantern_lc_read of the kind and key into
 * the object, then its response chunk after the bytes of out: result 0, the context
 * compute_fork_digest of the epoch of its attested slot. The statuses of lantern_lc_read and
 * lantern_reqresp_write_chunk. The scratch's size as it came. x19 lc, x20 the object, x21 out, x22
 * scratch, x23 node. Locals: L a ChunkHeader, L + 48 the fork, L + 56 the epoch, L + 64 the
 * scratch's size.
 */
LOCAL_FUNCTION node_lc_chunk
    ENTER 80
    mov     x19, x0
    mov     x20, x3
    mov     x21, x4
    mov     x22, x5
    mov     x23, x6
    ldr     x9, [x22]
    str     x9, [sp, #(L + 64)]
    MOVQ    x9, 24 + LC_UPDATE_ROOM
    str     x9, [x20]
    mov     x3, x20
    add     x4, sp, #(L + 48)
    bl      lantern_lc_read
    cbnz    x0, 9f
    ldr     x9, [x20, #8]                   /* attested_header.beacon.slot, a bootstrap's header.beacon.slot */
    add     x9, x20, x9
    ldr     x10, [sp, #(L + 48)]
    cmp     x10, #FORK_CAPELLA
    b.lo    1f
    ldr     w11, [x9]
    add     x9, x9, x11
1:  ldr     x9, [x9]
    mov     x10, #SLOTS_PER_EPOCH
    udiv    x9, x9, x10
    str     x9, [sp, #(L + 56)]
    mov     x9, #CHUNK_RESPONSE
    mov     x10, #4
    stp     x9, x10, [sp, #(L + ChunkHeader_kind)]
    str     xzr, [sp, #(L + ChunkHeader_result)]
    str     xzr, [sp, #(L + ChunkHeader_context)]
    add     x0, x23, #Node_genesis_validators_root
    add     x1, sp, #(L + 56)
    add     x2, x23, #Node_config
    mov     x3, x22
    add     x4, sp, #(L + ChunkHeader_context)
    ldr     x15, [sp, #(L + 48)]
    FORK_CALL compute_fork_digest
    cbnz    x0, 8f
    ldr     x9, [sp, #(L + 64)]             /* the scratch's size again (asm-standard: before each call) */
    str     x9, [x22]
    add     x0, sp, #L
    mov     x1, x20
    mov     x2, x22
    mov     x3, x21
    bl      lantern_reqresp_write_chunk
9:  ldr     x9, [sp, #(L + 64)]             /* the scratch's size, as it came */
    str     x9, [x22]
    LEAVE 80
8:  mov     x0, #LANTERN_INVALID_ENCODING
    b       9b
END_FUNCTION node_lc_chunk

/* L1: (result, payload, scratch, out) -> status: a response chunk of the result, with no context bytes, after the bytes of out. Locals: L a ChunkHeader. */
LOCAL_FUNCTION node_lc_error_chunk
    FRAME 48
    mov     x9, #CHUNK_RESPONSE
    stp     x9, xzr, [sp, #(16 + ChunkHeader_kind)]
    str     x0, [sp, #(16 + ChunkHeader_result)]
    str     xzr, [sp, #(16 + ChunkHeader_context)]
    add     x0, sp, #16
    bl      lantern_reqresp_write_chunk
    UNFRAME 48
END_FUNCTION node_lc_error_chunk

/*
 * L1: a light client request of the stream entry x0 (node.md): its x2 bytes at x1 (none with 0) to
 * a new id, a NODE_WORK_LC_SERVE of them with the light client store as state_c; the stream takes
 * NODE_STREAM_SERVING, its list empty. x21 the entry, x22 the id. Locals: L a ByteList of the bytes.
 */
LOCAL_FUNCTION node_lc_request
    ENTER 64
    mov     x21, x0
    mov     x22, #0
    cbz     x2, 1f
    add     x9, sp, #L
    add     x10, x2, #24
    mov     x11, #24
    stp     x10, x11, [x9]
    str     x2, [x9, #16]
    add     x0, x9, #24
    bl      lantern_copy
    add     x0, sp, #L
    bl      node_put
    mov     x22, x0
1:  mov     x0, #NODE_WORK_LC_SERVE
    mov     x1, #0
    mov     x2, #0
    mov     x3, x22
    ldr     x4, [x21, #NodeStream_handle]
    ldr     x5, [x21, #NodeStream_method]
    bl      node_work
    mov     x9, #NODE_LC_ID
    str     x9, [x0, #NodeAction_state_c]
    mov     x9, #NODE_STREAM_SERVING
    str     x9, [x21, #NodeStream_state]
    str     xzr, [x21, #(NodeStream_list + 16)]
    LEAVE 64
END_FUNCTION node_lc_request

/*
 * L1: the NODE_EV_WORK_DONE x21 of a NODE_WORK_LC_SERVE (node.md): its bytes go, then the chunks to
 * the stream in a STREAM_WRITE and a STREAM_CLOSE, or a STREAM_RESET; then the stream goes. x19
 * the node, x24 the actions; x22 the stream, x25 the chunks' bytes. Locals: L the event's size.
 */
LOCAL_FUNCTION node_lc_served
    ENTER 16
    ldr     x1, [x21, #NodeAction_data]
    cbz     x1, 1f
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      node_ids
1:  ldr     x0, [x21, #NodeAction_target]
    bl      node_find_stream
    cmn     x0, #1
    b.eq    9f
    mov     x22, x1
    ldr     x9, [x21, #NodeEvent_result]
    cbnz    x9, 8f
    ldr     x25, [x21, #(NodeEvent_chunk + 16)]
    cbz     x25, 7f
    add     x0, x25, #(32 + 7)
    and     x0, x0, #~7
    str     x0, [sp, #L]
    bl      node_out
    cbz     x0, 8f
    ldr     x9, [sp, #L]
    mov     x10, #LIBP2P_EVENT_STREAM_WRITE
    stp     x9, x10, [x0]
    ldr     x10, [x22, #NodeStream_handle]
    stp     x10, x25, [x0, #16]
    add     x0, x0, #32
    add     x1, x21, #(NodeEvent_chunk + 24)
    mov     x2, x25
    bl      lantern_copy
7:  mov     x0, #LIBP2P_EVENT_STREAM_CLOSE
    ldr     x1, [x22, #NodeStream_handle]
    bl      node_out_handle
    mov     x0, x22
    bl      node_drop_stream
9:  LEAVE 16
8:  mov     x0, #LIBP2P_EVENT_STREAM_RESET
    ldr     x1, [x22, #NodeStream_handle]
    bl      node_out_handle
    mov     x0, x22
    bl      node_drop_stream
    LEAVE 16
END_FUNCTION node_lc_served
