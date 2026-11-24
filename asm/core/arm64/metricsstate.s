/*
 * The metrics' values of a head state, ARM64: in the object of each fork. Requirements:
 * docs/reference/metrics.md, lantern_metrics_state.
 */

/* x9 = the status of the validator x12 at the epoch e: 0 pending, 1 active, 2 exited, 3 withdrawable. Uses x10. */
.macro MS_STATUS e
    mov     x9, #0
    ldr     x10, [x12, #Validator_activation_epoch]
    cmp     x10, \e
    b.hi    91f
    mov     x9, #1
    ldr     x10, [x12, #Validator_exit_epoch]
    cmp     \e, x10
    b.lo    91f
    mov     x9, #2
    ldr     x10, [x12, #Validator_withdrawable_epoch]
    cmp     \e, x10
    b.lo    91f
    mov     x9, #3
91:
.endm

/*
 * (state, block, out): x0 state, x1 block, x2 out, x3 the current epoch, x4 the previous epoch, x5
 * the current participation, x6 the previous participation, x12 a validator, x13 the validators
 * left. A leaf.
 */
SPEC_LEAF metrics_state
    mov     x9, #0                          /* out: zero */
1:  str     xzr, [x2, x9]
    add     x9, x9, #8
    cmp     x9, #MetricsState__mem
    b.lo    1b
    mov     x9, #1
    str     x9, [x2, #MetricsState_present]
    ldr     x9, [x1, #16]                   /* the block's state_root: bytes 148 to 180, as a number */
    cmp     x9, #180
    b.lo    2f
    ldr     x9, [x1, #8]
    add     x9, x9, x1
    ldr     x9, [x9, #172]
    str     x9, [x2, #MetricsState_state_root]
    mov     x9, #1
    str     x9, [x2, #MetricsState_state_root_present]
2:  LDQ     x3, x0, BeaconState_slot
    str     x3, [x2, #MetricsState_slot]
    lsr     x3, x3, #LOG2_SLOTS_PER_EPOCH   /* the current epoch, and the previous: one less, not below 0 */
    subs    x4, x3, #1
    csel    x4, xzr, x4, lo
    LDQ     x9, x0, BeaconState_finalized_checkpoint + Checkpoint_epoch
    str     x9, [x2, #MetricsState_finalized_epoch]
    LDQ     x9, x0, BeaconState_current_justified_checkpoint + Checkpoint_epoch
    str     x9, [x2, #MetricsState_current_justified_epoch]
    LDQ     x9, x0, BeaconState_previous_justified_checkpoint + Checkpoint_epoch
    str     x9, [x2, #MetricsState_previous_justified_epoch]
    LDQ     x9, x0, BeaconState_finalized_checkpoint + Checkpoint_root + 24
    str     x9, [x2, #MetricsState_finalized_root]
    LDQ     x9, x0, BeaconState_previous_justified_checkpoint + Checkpoint_root + 24
    str     x9, [x2, #MetricsState_previous_justified_root]
    LDQ     x9, x0, BeaconState_eth1_data + Eth1Data_deposit_count
    str     x9, [x2, #MetricsState_deposit_count]
.if FORK >= FORK_ALTAIR
    mov     x9, #1
    str     x9, [x2, #MetricsState_altair]
.endif
.if FORK >= FORK_ELECTRA
    mov     x9, #1
    str     x9, [x2, #MetricsState_electra]
    LDQ     x9, x0, BeaconState_pending_deposits + 8
    str     x9, [x2, #MetricsState_pending_deposits]
    LDQ     x9, x0, BeaconState_pending_partial_withdrawals + 8
    str     x9, [x2, #MetricsState_pending_partial_withdrawals]
    LDQ     x9, x0, BeaconState_pending_consolidations + 8
    str     x9, [x2, #MetricsState_pending_consolidations]
.endif
    PART    x12, x13, x0, BeaconState_validators
.if FORK >= FORK_ALTAIR
    PART    x5, x9, x0, BeaconState_current_epoch_participation
    PART    x6, x9, x0, BeaconState_previous_epoch_participation
.endif
    add     x7, x2, #MetricsState_current_validators
    add     x8, x2, #MetricsState_previous_validators
    /* each validator: its status at each epoch; and live */
4:  cbz     x13, 8f
    MS_STATUS x3
    ldr     x10, [x7, x9, lsl #3]
    add     x10, x10, #1
    str     x10, [x7, x9, lsl #3]
.if FORK >= FORK_ALTAIR
    ldrb    w11, [x5], #1                   /* active with a flag */
    cmp     x9, #1
    ccmp    w11, #0, #4, eq
    b.eq    5f
    ldr     x10, [x2, #MetricsState_current_live]
    add     x10, x10, #1
    str     x10, [x2, #MetricsState_current_live]
5:
.endif
    MS_STATUS x4
    ldr     x10, [x8, x9, lsl #3]
    add     x10, x10, #1
    str     x10, [x8, x9, lsl #3]
.if FORK >= FORK_ALTAIR
    ldrb    w11, [x6], #1
    cmp     x9, #1
    ccmp    w11, #0, #4, eq
    b.eq    6f
    ldr     x10, [x2, #MetricsState_previous_live]
    add     x10, x10, #1
    str     x10, [x2, #MetricsState_previous_live]
6:
.endif
    add     x12, x12, #Validator__mem
    sub     x13, x13, #1
    b       4b
8:  ldr     x9, [x2, #(MetricsState_current_validators + 8)]
    str     x9, [x2, #MetricsState_active_validators]
    mov     x0, #LANTERN_OK
    ret
SPEC_END metrics_state
