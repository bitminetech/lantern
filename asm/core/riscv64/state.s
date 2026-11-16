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

LEAF lantern_beacon_state_copy_size
    li      a3, BeaconState__fixed
    STATE_PARTS SIZE_PART
    sd      a3, 0(a2)
    RETURN_OK
END_FUNCTION lantern_beacon_state_copy_size

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

FUNCTION lantern_beacon_state_copy
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
END_FUNCTION lantern_beacon_state_copy

/* dst a0, src a1, n a2: 32 bytes at a time when both are 8-aligned, else a byte at a time. */
LEAF lantern_copy
    or      a3, a0, a1
    andi    a3, a3, 7
    bnez    a3, 3f
    li      a3, 32
1:  bltu    a2, a3, 2f
    ld      a4, 0(a1)
    ld      a5, 8(a1)
    ld      a6, 16(a1)
    ld      a7, 24(a1)
    sd      a4, 0(a0)
    sd      a5, 8(a0)
    sd      a6, 16(a0)
    sd      a7, 24(a0)
    addi    a1, a1, 32
    addi    a0, a0, 32
    addi    a2, a2, -32
    j       1b
2:  li      a3, 8
21: bltu    a2, a3, 3f
    ld      a4, 0(a1)
    sd      a4, 0(a0)
    addi    a1, a1, 8
    addi    a0, a0, 8
    addi    a2, a2, -8
    j       21b
3:  beqz    a2, 4f
    lbu     a4, 0(a1)
    sb      a4, 0(a0)
    addi    a1, a1, 1
    addi    a0, a0, 1
    addi    a2, a2, -1
    j       3b
4:  ret
END_FUNCTION lantern_copy

LEAF lantern_zero
    andi    a2, a0, 7
    bnez    a2, 3f
    li      a2, 8
1:  bltu    a1, a2, 3f
    sd      zero, 0(a0)
    addi    a0, a0, 8
    addi    a1, a1, -8
    j       1b
3:  beqz    a1, 4f
    sb      zero, 0(a0)
    addi    a0, a0, 1
    addi    a1, a1, -1
    j       3b
4:  ret
END_FUNCTION lantern_zero
