/*
 * Beacon state buffers, ARM64. Requirements: docs/reference/state.md.
 */

/* Room of an ExecutionPayloadHeader value with the longest extra_data. */
.set HEADER_ROOM, (ExecutionPayloadHeader__fixed + MAX_EXTRA_DATA_BYTES + 7) / 8 * 8

/* The parts of a BeaconState, in field order: PartRef offset, entry stride, StateRoom offset or -1. */
.macro STATE_PARTS m
    \m BeaconState_historical_roots, Bytes32__mem, -1
    \m BeaconState_eth1_data_votes, Eth1Data__mem, 8
    \m BeaconState_validators, Validator__mem, 0
    \m BeaconState_balances, 8, 0
    \m BeaconState_previous_epoch_participation, 1, 0
    \m BeaconState_current_epoch_participation, 1, 0
    \m BeaconState_inactivity_scores, 8, 0
    \m BeaconState_latest_execution_payload_header, 0, -1
    \m BeaconState_historical_summaries, HistoricalSummary__mem, 16
    \m BeaconState_pending_deposits, PendingDeposit__mem, 24
    \m BeaconState_pending_partial_withdrawals, PendingPartialWithdrawal__mem, 32
    \m BeaconState_pending_consolidations, PendingConsolidation__mem, 40
.endm

/* Check that the parts above are in field order. */
.set STATE_PART_LAST, 0
.macro STATE_PART_ORDER ref, stride, room
    .if (\ref) <= STATE_PART_LAST
    .error "STATE_PARTS: out of field order"
    .endif
    .set STATE_PART_LAST, \ref
.endm
STATE_PARTS STATE_PART_ORDER

/*
 * x9 = the capacity a copy gives one part of state x0 with room x1: its entry
 * bytes plus room, rounded up to 8. Also x10 = its entry bytes, x11 = its count.
 * Uses x12, x13.
 */
.macro PART_CAPACITY ref, stride, room
    PART    x12, x11, x0, \ref
    .if \stride
    mov     x13, #\stride
    mul     x10, x11, x13
    .if (\room) >= 0
    ldr     x9, [x1, #\room]
    madd    x9, x9, x13, x10
    .else
    mov     x9, x10
    .endif
    .else
    mov     x10, #0                         /* a nested value: its size, when present */
    cbz     x11, 91f
    ldr     x10, [x12]
91: MOVQ    x9, HEADER_ROOM
    cmp     x10, x9
    csel    x9, x10, x9, hi
    .endif
    add     x9, x9, #7
    and     x9, x9, #-8
.endm

.macro SIZE_PART ref, stride, room
    PART_CAPACITY \ref, \stride, \room
    add     x3, x3, x9
.endm

LEAF lantern_beacon_state_copy_size
    MOVQ    x3, BeaconState__fixed
    STATE_PARTS SIZE_PART
    str     x3, [x2]
    RETURN_OK
END_FUNCTION lantern_beacon_state_copy_size

/* x19 state, x20 room, x21 out, x22 cursor. */
.macro COPY_PART ref, stride, room
    mov     x0, x19
    mov     x1, x20
    PART_CAPACITY \ref, \stride, \room
    STQ     x22, x21, \ref                  /* out's PartRef: offset and count */
    STQ     x11, x21, (\ref) + 8
    add     x0, x21, x22
    mov     x1, x12
    mov     x2, x10
    add     x22, x22, x9
    bl      lantern_copy
.endm

FUNCTION lantern_beacon_state_copy
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    add     x2, sp, #L
    bl      lantern_beacon_state_copy_size
    ldr     x9, [sp, #L]
    ldr     x10, [x21]
    cmp     x10, x9
    b.lo    9f
    add     x0, x21, #8                     /* the fixed part, after out's own size */
    add     x1, x19, #8
    MOVQ    x2, BeaconState__fixed - 8
    bl      lantern_copy
    MOVQ    x22, BeaconState__fixed
    STATE_PARTS COPY_PART
    mov     x0, #LANTERN_OK
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_beacon_state_copy

LEAF lantern_copy
    cmp     x2, #64
    b.lo    2f
1:  ldp     q0, q1, [x1]
    ldp     q2, q3, [x1, #32]
    add     x1, x1, #64
    stp     q0, q1, [x0]
    stp     q2, q3, [x0, #32]
    add     x0, x0, #64
    sub     x2, x2, #64
    cmp     x2, #64
    b.hs    1b
2:  cbz     x2, 4f
3:  ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    subs    x2, x2, #1
    b.ne    3b
4:  ret
END_FUNCTION lantern_copy

LEAF lantern_zero
    cmp     x1, #16
    b.lo    2f
1:  stp     xzr, xzr, [x0], #16
    sub     x1, x1, #16
    cmp     x1, #16
    b.hs    1b
2:  cbz     x1, 4f
3:  strb    wzr, [x0], #1
    subs    x1, x1, #1
    b.ne    3b
4:  ret
END_FUNCTION lantern_zero
