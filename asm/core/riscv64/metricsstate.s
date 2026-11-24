/*
 * The metrics' values of a head state, RISC-V: in the object of each fork. Requirements:
 * docs/reference/metrics.md, lantern_metrics_state.
 */

# t0 = the status of the validator t5 at the epoch e: 0 pending, 1 active, 2 exited, 3 withdrawable. Uses t1.
.macro MS_STATUS e
    li      t0, 0
    ld      t1, Validator_activation_epoch(t5)
    bltu    \e, t1, 91f
    li      t0, 1
    ld      t1, Validator_exit_epoch(t5)
    bltu    \e, t1, 91f
    li      t0, 2
    ld      t1, Validator_withdrawable_epoch(t5)
    bltu    \e, t1, 91f
    li      t0, 3
91:
.endm

/*
 * (state, block, out): a0 state, a1 block, a2 out, a3 the current epoch, a4 the previous epoch, a5
 * the current participation, a6 the previous participation, t5 a validator, t6 the validators left.
 * A leaf.
 */
SPEC_LEAF metrics_state
    li      t0, 0                           # out: zero
    li      t1, MetricsState__mem
1:  add     t2, a2, t0
    sd      zero, 0(t2)
    addi    t0, t0, 8
    bltu    t0, t1, 1b
    li      t0, 1
    sd      t0, MetricsState_present(a2)
    ld      t0, 16(a1)                      # the block's state_root: bytes 148 to 180, as a number
    li      t1, 180
    bltu    t0, t1, 2f
    ld      t0, 8(a1)
    add     t0, t0, a1
    ld      t0, 172(t0)
    sd      t0, MetricsState_state_root(a2)
    li      t0, 1
    sd      t0, MetricsState_state_root_present(a2)
2:  LDQ     a3, a0, BeaconState_slot
    sd      a3, MetricsState_slot(a2)
    srli    a3, a3, LOG2_SLOTS_PER_EPOCH    # the current epoch, and the previous: one less, not below 0
    mv      a4, a3
    beqz    a4, 3f
    addi    a4, a4, -1
3:  LDQ     t0, a0, BeaconState_finalized_checkpoint + Checkpoint_epoch
    sd      t0, MetricsState_finalized_epoch(a2)
    LDQ     t0, a0, BeaconState_current_justified_checkpoint + Checkpoint_epoch
    sd      t0, MetricsState_current_justified_epoch(a2)
    LDQ     t0, a0, BeaconState_previous_justified_checkpoint + Checkpoint_epoch
    sd      t0, MetricsState_previous_justified_epoch(a2)
    LDQ     t0, a0, BeaconState_finalized_checkpoint + Checkpoint_root + 24
    sd      t0, MetricsState_finalized_root(a2)
    LDQ     t0, a0, BeaconState_previous_justified_checkpoint + Checkpoint_root + 24
    sd      t0, MetricsState_previous_justified_root(a2)
    LDQ     t0, a0, BeaconState_eth1_data + Eth1Data_deposit_count
    sd      t0, MetricsState_deposit_count(a2)
.if FORK >= FORK_ALTAIR
    li      t0, 1
    sd      t0, MetricsState_altair(a2)
.endif
.if FORK >= FORK_ELECTRA
    li      t0, 1
    sd      t0, MetricsState_electra(a2)
    LDQ     t0, a0, BeaconState_pending_deposits + 8
    sd      t0, MetricsState_pending_deposits(a2)
    LDQ     t0, a0, BeaconState_pending_partial_withdrawals + 8
    sd      t0, MetricsState_pending_partial_withdrawals(a2)
    LDQ     t0, a0, BeaconState_pending_consolidations + 8
    sd      t0, MetricsState_pending_consolidations(a2)
.endif
    PART    t5, t6, a0, BeaconState_validators
.if FORK >= FORK_ALTAIR
    PART    a5, t0, a0, BeaconState_current_epoch_participation
    PART    a6, t0, a0, BeaconState_previous_epoch_participation
.endif
4:  beqz    t6, 8f                          # each validator: its status at each epoch; and live
    MS_STATUS a3
    slli    t2, t0, 3
    add     t2, t2, a2
    ld      t3, MetricsState_current_validators(t2)
    addi    t3, t3, 1
    sd      t3, MetricsState_current_validators(t2)
.if FORK >= FORK_ALTAIR
    lbu     t3, 0(a5)                       # active with a flag
    addi    a5, a5, 1
    li      t2, 1
    bne     t0, t2, 5f
    beqz    t3, 5f
    ld      t3, MetricsState_current_live(a2)
    addi    t3, t3, 1
    sd      t3, MetricsState_current_live(a2)
5:
.endif
    MS_STATUS a4
    slli    t2, t0, 3
    add     t2, t2, a2
    ld      t3, MetricsState_previous_validators(t2)
    addi    t3, t3, 1
    sd      t3, MetricsState_previous_validators(t2)
.if FORK >= FORK_ALTAIR
    lbu     t3, 0(a6)
    addi    a6, a6, 1
    li      t2, 1
    bne     t0, t2, 6f
    beqz    t3, 6f
    ld      t3, MetricsState_previous_live(a2)
    addi    t3, t3, 1
    sd      t3, MetricsState_previous_live(a2)
6:
.endif
    addi    t5, t5, Validator__mem
    addi    t6, t6, -1
    j       4b
8:  ld      t0, (MetricsState_current_validators + 8)(a2)
    sd      t0, MetricsState_active_validators(a2)
    li      a0, LANTERN_OK
    ret
SPEC_END metrics_state
