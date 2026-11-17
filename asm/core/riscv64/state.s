/*
 * Beacon state buffers, RISC-V. Requirements: docs/reference/state.md.
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

/*
 * t0 = the capacity a copy gives one part of state a0 with room a1: its entry
 * bytes plus room, rounded up to 8. Also t1 = its entry bytes, t2 = its count,
 * t3 = where its entries are. Uses t4, a7.
 */
.macro PART_CAPACITY ref, stride, room
    PART    t3, t2, a0, \ref
    .if \stride
    li      t4, \stride
    mul     t1, t2, t4
    .if (\room) >= 0
    ld      t0, (\room)(a1)
    mul     t0, t0, t4
    add     t0, t0, t1
    .else
    mv      t0, t1
    .endif
    .else
    li      t1, 0                           # a nested value: its size, when present
    beqz    t2, 91f
    ld      t1, 0(t3)
91: li      t0, HEADER_ROOM
    bleu    t1, t0, 92f
    mv      t0, t1
92:
    .endif
    addi    t0, t0, 7
    andi    t0, t0, -8
.endm

.macro SIZE_PART ref, stride, room
    PART_CAPACITY \ref, \stride, \room
    add     a3, a3, t0
.endm

SPEC_LEAF beacon_state_copy_size
    li      a3, BeaconState__fixed
    STATE_PARTS SIZE_PART
    sd      a3, 0(a2)
    RETURN_OK
SPEC_END beacon_state_copy_size

/* s1 state, s2 room, s3 out, s4 cursor. */
.macro COPY_PART ref, stride, room
    mv      a0, s1
    mv      a1, s2
    PART_CAPACITY \ref, \stride, \room
    STQ     s4, s3, \ref                    # out's PartRef: offset and count
    STQ     t2, s3, (\ref) + 8
    add     a0, s3, s4
    mv      a1, t3
    mv      a2, t1
    add     s4, s4, t0
    call    lantern_copy
.endm

SPEC_FUNCTION beacon_state_copy
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    addi    a2, sp, L
    call    lantern_beacon_state_copy_size
    ld      t0, L(sp)
    ld      t1, 0(s3)
    bltu    t1, t0, 9f
    addi    a0, s3, 8                       # the fixed part, after out's own size
    addi    a1, s1, 8
    li      a2, BeaconState__fixed - 8
    call    lantern_copy
    li      s4, BeaconState__fixed
    STATE_PARTS COPY_PART
    li      a0, LANTERN_OK
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END beacon_state_copy
