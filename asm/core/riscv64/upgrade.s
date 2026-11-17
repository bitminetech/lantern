/*
 * Fork upgrades, RISC-V. Requirements: docs/reference/fork-upgrades.md.
 * The object of a fork reads the state of the fork before with the PRE_ layouts.
 */

.if BeaconState_validators != PRE_BeaconState_validators
.error "the validators of the states before and after an upgrade are not at one offset"
.endif

/* How an upgrade fills a part of the new state. */
.set UP_COPY, 1                     /* the part of the same name in the state before */
.set UP_ZEROS, 2                    /* one zero entry for each validator */
.set UP_EMPTY, 3                    /* no entries */
.set UP_HEADER_EMPTY, 4             /* ExecutionPayloadHeader() */
.set UP_HEADER, 5                   /* the header of the state before, with the new fields zero */
.set UP_DEPOSITS, 6                 /* electra: room for s8 entries, appended after the parts */

/* The parts of the new state, in field order: name, stride (0: one nested value), StateRoom offset or -1, how. */
.macro UP_PARTS m
    \m historical_roots, Bytes32__mem, 48, UP_COPY
    \m eth1_data_votes, Eth1Data__mem, 8, UP_COPY
    \m validators, Validator__mem, 0, UP_COPY
    \m balances, 8, 0, UP_COPY
.if FORK == FORK_ALTAIR
    \m previous_epoch_participation, 1, 0, UP_ZEROS
    \m current_epoch_participation, 1, 0, UP_ZEROS
    \m inactivity_scores, 8, 0, UP_ZEROS
.else
    \m previous_epoch_participation, 1, 0, UP_COPY
    \m current_epoch_participation, 1, 0, UP_COPY
    \m inactivity_scores, 8, 0, UP_COPY
.endif
.if FORK == FORK_BELLATRIX
    \m latest_execution_payload_header, 0, -1, UP_HEADER_EMPTY
.elseif FORK == FORK_CAPELLA || FORK == FORK_DENEB
    \m latest_execution_payload_header, 0, -1, UP_HEADER
.elseif FORK > FORK_DENEB
    \m latest_execution_payload_header, 0, -1, UP_COPY
.endif
.if FORK == FORK_CAPELLA
    \m historical_summaries, HistoricalSummary__mem, 16, UP_EMPTY
.elseif FORK > FORK_CAPELLA
    \m historical_summaries, HistoricalSummary__mem, 16, UP_COPY
.endif
.if FORK == FORK_ELECTRA
    \m pending_deposits, PendingDeposit__mem, 24, UP_DEPOSITS
    \m pending_partial_withdrawals, PendingPartialWithdrawal__mem, 32, UP_EMPTY
    \m pending_consolidations, PendingConsolidation__mem, 40, UP_EMPTY
.elseif FORK > FORK_ELECTRA
    \m pending_deposits, PendingDeposit__mem, 24, UP_COPY
    \m pending_partial_withdrawals, PendingPartialWithdrawal__mem, 32, UP_COPY
    \m pending_consolidations, PendingConsolidation__mem, 40, UP_COPY
.endif
.endm

/* Check that the parts above are the parts of STATE_PARTS (state.s), in its order. */
.set UP_PART_LAST, 0
.macro UP_PART_ORDER name, stride, room, how
    .if (BeaconState_\name) <= UP_PART_LAST
    .error "UP_PARTS: out of field order"
    .endif
    .set UP_PART_LAST, BeaconState_\name
    .set UP_PART_COUNT, UP_PART_COUNT + 1
.endm
.macro STATE_PART_COUNT ref, stride, room
    .set STATE_PART_TOTAL, STATE_PART_TOTAL + 1
.endm
.set UP_PART_COUNT, 0
.set STATE_PART_TOTAL, 0
UP_PARTS UP_PART_ORDER
STATE_PARTS STATE_PART_COUNT
.if UP_PART_COUNT != STATE_PART_TOTAL
.error "UP_PARTS: not the parts of STATE_PARTS"
.endif

/* The fixed fields that the new state takes from the state before. */
.macro UP_FIXED m
    \m genesis_time
    \m genesis_validators_root
    \m slot
    \m latest_block_header
    \m block_roots
    \m state_roots
    \m eth1_data
    \m eth1_deposit_index
    \m randao_mixes
    \m slashings
    \m justification_bits
    \m previous_justified_checkpoint
    \m current_justified_checkpoint
    \m finalized_checkpoint
.if FORK >= FORK_BELLATRIX
    \m current_sync_committee
    \m next_sync_committee
.endif
.if FORK >= FORK_DENEB
    \m next_withdrawal_index
    \m next_withdrawal_validator_index
.endif
.if FORK >= FORK_FULU
    \m deposit_requests_start_index
    \m deposit_balance_to_consume
    \m exit_balance_to_consume
    \m earliest_exit_epoch
    \m consolidation_balance_to_consume
    \m earliest_consolidation_epoch
.endif
.endm

/* Copy the fixed field name of the state before s1 to the new state s5. */
.macro UP_COPY_FIELD name
    .if BeaconState_\name\()__mem != PRE_BeaconState_\name\()__mem
    .error "UP_FIXED: a field changes its size"
    .endif
    ADDQ    a0, s5, BeaconState_\name
    ADDQ    a1, s1, PRE_BeaconState_\name
    li      a2, BeaconState_\name\()__mem
    call    lantern_copy
.endm

/* t0 = the entries of the new part name. */
.macro UP_COUNT name, how
.if (\how) == UP_COPY
    LDQ     t0, s1, PRE_BeaconState_\name + 8
.elseif (\how) == UP_ZEROS
    LDQ     t0, s1, PRE_BeaconState_validators + 8
.elseif (\how) == UP_DEPOSITS
    mv      t0, s8
.elseif (\how) == UP_EMPTY
    li      t0, 0
.else
    li      t0, 1                           # one header value
.endif
.endm

/* t1 = the bytes of a part of t0 entries of stride with the room at room of StateRoom s2, rounded up to 8. Uses t2. */
.macro UP_CAPACITY stride, room
.if \stride
    .if (\room) >= 0
    ld      t1, \room(s2)
    add     t1, t1, t0
    .else
    mv      t1, t0
    .endif
    li      t2, \stride
    mul     t1, t1, t2
    addi    t1, t1, 7
    andi    t1, t1, -8
.else
    li      t1, HEADER_ROOM
.endif
.endm

.macro UP_SIZE_PART name, stride, room, how
    UP_COUNT \name, \how
    UP_CAPACITY \stride, \room
    add     s6, s6, t1
.endm

/* Write the part name of the new state s5 at cursor s6, from the state before s1, and move the cursor. */
.macro UP_WRITE_PART name, stride, room, how
    UP_COUNT \name, \how
    UP_CAPACITY \stride, \room
    STQ     s6, s5, BeaconState_\name
.if (\how) == UP_DEPOSITS
    STQ     zero, s5, BeaconState_\name + 8
.else
    STQ     t0, s5, BeaconState_\name + 8
.endif
    add     a0, s5, s6
    add     s6, s6, t1
.if (\how) == UP_COPY
    PART    a1, a2, s1, PRE_BeaconState_\name
    .if \stride
    li      t2, \stride
    mul     a2, a2, t2
    .else
    ld      a2, 0(a1)                       # a nested value: its size
    .endif
    call    lantern_copy
.elseif (\how) == UP_ZEROS
    li      t2, \stride
    mul     a1, t0, t2
    call    lantern_zero
.elseif (\how) == UP_HEADER_EMPTY
    call    upgrade_empty_header
.elseif (\how) == UP_HEADER
    PART    a1, a2, s1, PRE_BeaconState_latest_execution_payload_header
    call    upgrade_header
.endif
.endm

.if FORK == FORK_BELLATRIX
/* ExecutionPayloadHeader() at a0. Locals: sp+0 the header. */
LOCAL_FUNCTION upgrade_empty_header
    FRAME 16
    sd      a0, 0(sp)
    li      a1, ExecutionPayloadHeader__fixed
    call    lantern_zero
    ld      a0, 0(sp)
    li      t0, ExecutionPayloadHeader__fixed
    sd      t0, 0(a0)                       # its size
    STQ     t0, a0, ExecutionPayloadHeader_extra_data   # the empty extra_data part, after the fixed fields
    UNFRAME 16
END_FUNCTION upgrade_empty_header
.endif

.if FORK == FORK_CAPELLA || FORK == FORK_DENEB
/* The header fields of the fork before, which the new header takes. */
.macro UP_HEADER_FIELDS m
    \m parent_hash
    \m fee_recipient
    \m state_root
    \m receipts_root
    \m logs_bloom
    \m prev_randao
    \m block_number
    \m gas_limit
    \m gas_used
    \m timestamp
    \m base_fee_per_gas
    \m block_hash
    \m transactions_root
.if FORK == FORK_DENEB
    \m withdrawals_root
.endif
.endm

.macro UP_COPY_HEADER_FIELD name
    ld      a0, 0(sp)
    ld      a1, 8(sp)
    ADDQ    a0, a0, ExecutionPayloadHeader_\name
    ADDQ    a1, a1, PRE_ExecutionPayloadHeader_\name
    li      a2, ExecutionPayloadHeader_\name\()__mem
    call    lantern_copy
.endm

/* The header of the fork at a0 from the header a1 of the fork before: its fields and extra_data, the new fields zero. */
LOCAL_FUNCTION upgrade_header
    FRAME 16
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    li      a1, ExecutionPayloadHeader__fixed
    call    lantern_zero
    UP_HEADER_FIELDS UP_COPY_HEADER_FIELD
    ld      a0, 0(sp)
    ld      t3, 8(sp)
    PART    a1, a2, t3, PRE_ExecutionPayloadHeader_extra_data
    li      t0, ExecutionPayloadHeader__fixed
    STQ     t0, a0, ExecutionPayloadHeader_extra_data
    STQ     a2, a0, ExecutionPayloadHeader_extra_data + 8
    add     t1, t0, a2
    addi    t1, t1, 7
    andi    t1, t1, -8
    sd      t1, 0(a0)                       # its size
    add     a0, a0, t0
    call    lantern_copy
    UNFRAME 16
END_FUNCTION upgrade_header
.endif

.if FORK == FORK_ELECTRA
/* L0: a0 = the pending deposits that upgrade_to_electra appends for the state before a0. A leaf. */
LOCAL_FUNCTION upgrade_deposit_count
    UNWIND_END_PROLOGUE
    PART    a1, a2, a0, PRE_BeaconState_validators
    PART    a3, a4, a0, PRE_BeaconState_balances
    li      a0, 0
    li      a5, MIN_ACTIVATION_BALANCE
1:  beqz    a2, 3f
    ld      t0, Validator_activation_epoch(a1)
    li      t1, -1
    beq     t0, t1, 2f                      # activation_epoch == FAR_FUTURE_EPOCH: a pending deposit of its balance
    lbu     t0, Validator_withdrawal_credentials(a1)
    li      t1, COMPOUNDING_WITHDRAWAL_PREFIX
    bne     t0, t1, 25f
    ld      t0, 0(a3)
    bleu    t0, a5, 25f                     # a compounding validator's excess above MIN_ACTIVATION_BALANCE
2:  addi    a0, a0, 1
25: addi    a1, a1, Validator__mem
    addi    a3, a3, 8
    addi    a2, a2, -1
    j       1b
3:  ret
END_FUNCTION upgrade_deposit_count

/* dst = 1 when the key of validator index a is above that of b, else 0; the key is (activation_eligibility_epoch, index). Uses t5, t6. */
.macro KEY_GT dst, a, b
    slli    t5, \a, 7
    add     t5, a2, t5
    ld      t5, Validator_activation_eligibility_epoch(t5)
    slli    t6, \b, 7
    add     t6, a2, t6
    ld      t6, Validator_activation_eligibility_epoch(t6)
    sltu    \dst, t6, t5
    bne     t5, t6, 95f
    sltu    \dst, \b, \a
95:
.endm

/* Sift the entry at root down the heap of entries below end, at a0, by key. Uses t0-t6. */
.macro ELIGIBILITY_SIFT root, end
97: slli    t0, \root, 1
    addi    t0, t0, 1                       # child = 2 * root + 1
    bgeu    t0, \end, 98f
    slli    t1, t0, 3
    add     t1, a0, t1
    ld      t1, 0(t1)
    addi    t2, t0, 1
    bgeu    t2, \end, 96f
    slli    t3, t2, 3
    add     t3, a0, t3
    ld      t3, 0(t3)
    KEY_GT  t4, t3, t1                      # the larger child
    beqz    t4, 96f
    mv      t0, t2
    mv      t1, t3
96: slli    t3, \root, 3
    add     t3, a0, t3
    ld      t2, 0(t3)
    KEY_GT  t4, t1, t2
    beqz    t4, 98f
    sd      t1, 0(t3)
    slli    t4, t0, 3
    add     t4, a0, t4
    sd      t2, 0(t4)
    mv      \root, t0
    j       97b
98:
.endm

/* L0: sort the a1 validator indices at a0 by (activation_eligibility_epoch, index) of the validators at a2 (heapsort). A leaf. */
LOCAL_FUNCTION sort_by_eligibility
    UNWIND_END_PROLOGUE
    li      t0, 2
    bltu    a1, t0, 9f
    srli    a3, a1, 1
1:  beqz    a3, 2f
    addi    a3, a3, -1
    mv      a4, a3
    ELIGIBILITY_SIFT a4, a1
    j       1b
2:  mv      a5, a1
3:  addi    a5, a5, -1
    beqz    a5, 9f
    ld      t0, 0(a0)
    slli    t1, a5, 3
    add     t1, a0, t1
    ld      t2, 0(t1)
    sd      t2, 0(a0)
    sd      t0, 0(t1)
    li      a4, 0
    ELIGIBILITY_SIFT a4, a5
    j       3b
9:  ret
END_FUNCTION sort_by_eligibility

.if (Validator_pubkey != PendingDeposit_pubkey) || (Validator_withdrawal_credentials != PendingDeposit_withdrawal_credentials) || (PendingDeposit_amount != 80)
.error "upgrade_to_electra copies the pubkey and credentials of a Validator into a PendingDeposit in one block"
.endif
.endif

.if FORK >= FORK_ALTAIR
/* s1 pre, s2 room, s3 size, s6 total, s8 electra: pending deposits. */
SPEC_FUNCTION upgrade_size
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
.if FORK == FORK_ELECTRA
    call    upgrade_deposit_count
    mv      s8, a0
.endif
    li      s6, BeaconState__fixed
    UP_PARTS UP_SIZE_PART
    sd      s6, 0(s3)
    li      a0, LANTERN_OK
    LEAVE 16
SPEC_END upgrade_size
.endif

.if FORK == FORK_ALTAIR
/*
 * s1 state, s2 pre, s3 scratch, s4 the entry, s5 entries left, s6 committee, s7 flags mask,
 * s8 scratch size, s9 the size callees get. Locals: L flags (FLAGS_BYTES).
 */
SPEC_FUNCTION translate_participation
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    NEED_SCRATCH s3, s1, 2, 9f
    ld      s8, 0(s3)
    LDQ     t2, s1, BeaconState_validators + 8
    SCRATCH_LIST s6, s3, s8, 0, t2          # the committee: the last list
    SCRATCH_GIVE s3, s8, 1, t2
    ld      s9, 0(s3)
    PART    s4, s5, s2, PRE_BeaconState_previous_epoch_attestations
1:  beqz    s5, 8f                          # for attestation in pending_attestations
    li      t0, FLAGS_BYTES
    sd      t0, L(sp)
    mv      a0, s1                          # participation_flag_indices = get_attestation_participation_flag_indices(state, data, inclusion_delay)
    ADDQ    a1, s4, PRE_PendingAttestation_data
    ADDQ    a2, s4, PRE_PendingAttestation_inclusion_delay
    addi    a3, sp, L
    call    lantern_get_attestation_participation_flag_indices
    bnez    a0, 7f
    li      s7, 0                           # the flags as one mask: add_flag of each
    ld      t0, (L + LIST_COUNT)(sp)
    addi    t1, sp, (L + LIST_FIXED)
2:  beqz    t0, 3f
    ld      t2, 0(t1)
    addi    t1, t1, 8
    li      t3, 1
    sll     t3, t3, t2
    or      s7, s7, t3
    addi    t0, t0, -1
    j       2b
3:  sd      s9, 0(s3)
    mv      a0, s1                          # committee = get_beacon_committee(state, data.slot, data.index)
    ADDQ    a1, s4, PRE_PendingAttestation_data + PRE_AttestationData_slot
    ADDQ    a2, s4, PRE_PendingAttestation_data + PRE_AttestationData_index
    mv      a3, s3
    mv      a4, s6
    call    lantern_get_beacon_committee
    bnez    a0, 7f
    PART    t0, t1, s4, PRE_PendingAttestation_aggregation_bits
    PART    t2, t3, s1, BeaconState_previous_epoch_participation
    ld      t4, LIST_COUNT(s6)
    addi    t5, s6, LIST_FIXED
    li      t6, 0
4:  bgeu    t6, t4, 6f                      # each committee member whose aggregation bit is set
    bgeu    t6, t1, 6f
    srli    a1, t6, 3
    add     a1, t0, a1
    lbu     a1, 0(a1)
    andi    a2, t6, 7
    srl     a1, a1, a2
    andi    a1, a1, 1
    beqz    a1, 5f
    slli    a1, t6, 3
    add     a1, t5, a1
    ld      a1, 0(a1)
    add     a1, t2, a1
    lbu     a2, 0(a1)
    or      a2, a2, s7
    sb      a2, 0(a1)
5:  addi    t6, t6, 1
    j       4b
6:  ld      t0, 0(s4)                       # the next nested value
    add     s4, s4, t0
    addi    s5, s5, -1
    j       1b
8:  li      a0, LANTERN_OK
7:  sd      s8, 0(s3)
    LEAVE 64
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
SPEC_END translate_participation
.endif

.if FORK >= FORK_FULU
/* s1 state, s2 scratch, s3 out, s4 scratch size, s5 i. Locals: L epoch. */
SPEC_FUNCTION initialize_proposer_lookahead
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    NEED_SCRATCH s2, s1, 2, 9f
    ld      s4, 0(s2)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    li      s5, 0
1:  li      t0, MIN_SEED_LOOKAHEAD + 1      # for i in range(MIN_SEED_LOOKAHEAD + 1)
    bgeu    s5, t0, 8f
    sd      s4, 0(s2)
    mv      a0, s1                          # lookahead.extend(get_beacon_proposer_indices(state, current_epoch + i))
    addi    a1, sp, L
    mv      a2, s2
    li      t0, 8 * SLOTS_PER_EPOCH
    mul     t0, s5, t0
    add     a3, s3, t0
    call    lantern_get_beacon_proposer_indices
    bnez    a0, 7f
    ld      t0, L(sp)
    addi    t1, t0, 1
    bltu    t1, t0, 6f
    sd      t1, L(sp)
    addi    s5, s5, 1
    j       1b
8:  li      a0, LANTERN_OK
7:  sd      s4, 0(s2)
    LEAVE 16
6:  li      a0, LANTERN_INVALID_OVERFLOW
    j       7b
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END initialize_proposer_lookahead
.endif

/*
 * The upgrade of the fork, under its spec name.
 * s1 pre, s2 room, s3 config, s4 scratch, s5 out, s6 cursor, s7 validator count,
 * s8 electra: pending deposits, s9 scratch size, s10 electra: the pre_activation list.
 * Locals: L size, L+8 epoch, L+16 a number, L+24 index, L+32 PendingDeposit (PendingDeposit__mem).
 */
.macro UPGRADE_FUNCTION name, version
SPEC_FUNCTION \name
    ENTER 240
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      s9, 0(s4)
    mv      a0, s1
    mv      a1, s2
    addi    a2, sp, L
    call    lantern_upgrade_size
    ld      t0, L(sp)
    ld      t1, 0(s5)
    bltu    t1, t0, 9f
.if FORK == FORK_ALTAIR
    NEED_SCRATCH_B s4, s1, 2, SYNC_COMMITTEE_SCRATCH, 9f
.elseif FORK == FORK_ELECTRA || FORK == FORK_FULU
    NEED_SCRATCH s4, s1, 2, 9f
.endif
    LDQ     s7, s1, PRE_BeaconState_validators + 8
.if FORK == FORK_ELECTRA
    mv      a0, s1
    call    upgrade_deposit_count
    mv      s8, a0
.endif
    addi    a0, s5, 8                       # the fixed part, after out's own size: zero, then the shared fields
    li      a1, BeaconState__fixed - 8
    call    lantern_zero
    UP_FIXED UP_COPY_FIELD
    ADDQ    t0, s1, PRE_BeaconState_fork + PRE_Fork_current_version
    lw      t1, 0(t0)
    ADDQ    t0, s5, BeaconState_fork        # fork = Fork(pre.fork.current_version, the fork's version, epoch)
    sw      t1, Fork_previous_version(t0)
    lw      t1, \version(s3)
    sw      t1, Fork_current_version(t0)
    LDQ     t1, s1, PRE_BeaconState_slot
    srli    t1, t1, LOG2_SLOTS_PER_EPOCH
    sd      t1, Fork_epoch(t0)
    sd      t1, (L + 8)(sp)
    li      s6, BeaconState__fixed          # the parts, in field order
    UP_PARTS UP_WRITE_PART
.if FORK == FORK_ALTAIR
    sd      s9, 0(s4)
    mv      a0, s5                          # translate_participation(post, pre.previous_epoch_attestations)
    mv      a1, s1
    mv      a2, s4
    call    lantern_translate_participation
    bnez    a0, 7f
    sd      s9, 0(s4)
    mv      a0, s5                          # post.current_sync_committee = get_next_sync_committee(post)
    mv      a1, s4
    ADDQ    a2, s5, BeaconState_current_sync_committee
    call    lantern_get_next_sync_committee
    bnez    a0, 7f
    sd      s9, 0(s4)
    mv      a0, s5                          # post.next_sync_committee = get_next_sync_committee(post)
    mv      a1, s4
    ADDQ    a2, s5, BeaconState_next_sync_committee
    call    lantern_get_next_sync_committee
    bnez    a0, 7f
.elseif FORK == FORK_ELECTRA
    addi    a0, sp, (L + 8)                 # earliest_exit_epoch = compute_activation_exit_epoch(epoch)
    addi    a1, sp, (L + 16)
    call    lantern_compute_activation_exit_epoch
    bnez    a0, 7f
    ld      t0, (L + 16)(sp)
    STQ     t0, s5, BeaconState_earliest_consolidation_epoch
    PART    t1, t2, s5, BeaconState_validators
    li      t4, -1
1:  beqz    t2, 2f                          # max with each exit_epoch other than FAR_FUTURE_EPOCH
    ld      t3, Validator_exit_epoch(t1)
    addi    t1, t1, Validator__mem
    addi    t2, t2, -1
    beq     t3, t4, 1b
    bleu    t3, t0, 1b
    mv      t0, t3
    j       1b
2:  addi    t0, t0, 1                       # earliest_exit_epoch += 1
    beqz    t0, 6f
    STQ     t0, s5, BeaconState_earliest_exit_epoch
    li      t0, -1                          # UNSET_DEPOSIT_REQUESTS_START_INDEX
    STQ     t0, s5, BeaconState_deposit_requests_start_index
    sd      s9, 0(s4)
    mv      a0, s5                          # exit_balance_to_consume = get_activation_exit_churn_limit(post)
    mv      a1, s3
    mv      a2, s4
    addi    a3, sp, (L + 16)
    call    lantern_get_activation_exit_churn_limit
    bnez    a0, 7f
    ld      t0, (L + 16)(sp)
    STQ     t0, s5, BeaconState_exit_balance_to_consume
    sd      s9, 0(s4)
    mv      a0, s5                          # consolidation_balance_to_consume = get_consolidation_churn_limit(post)
    mv      a1, s3
    mv      a2, s4
    addi    a3, sp, (L + 16)
    call    lantern_get_consolidation_churn_limit
    bnez    a0, 7f
    ld      t0, (L + 16)(sp)
    STQ     t0, s5, BeaconState_consolidation_balance_to_consume
    SCRATCH_LIST s10, s4, s9, 0, s7         # pre_activation: the last list of scratch
    PART    t1, t2, s5, BeaconState_validators
    addi    t3, s10, LIST_FIXED
    li      t4, 0
    li      t6, -1
3:  bgeu    t4, t2, 4f                      # the validators with activation_epoch FAR_FUTURE_EPOCH, in index order
    ld      t5, Validator_activation_epoch(t1)
    addi    t1, t1, Validator__mem
    bne     t5, t6, 35f
    sd      t4, 0(t3)
    addi    t3, t3, 8
35: addi    t4, t4, 1
    j       3b
4:  addi    t0, s10, LIST_FIXED
    sub     t3, t3, t0
    srli    t3, t3, 3
    sd      t3, LIST_COUNT(s10)
    addi    a0, s10, LIST_FIXED             # sorted by (activation_eligibility_epoch, index)
    mv      a1, t3
    PART    a2, t0, s5, BeaconState_validators
    call    sort_by_eligibility
    addi    a0, sp, (L + 32 + PendingDeposit_signature)   # signature: G2_POINT_AT_INFINITY; slot: GENESIS_SLOT
    li      a1, 96
    call    lantern_zero
    li      t0, 0xc0
    sb      t0, (L + 32 + PendingDeposit_signature)(sp)
    sd      zero, (L + 32 + PendingDeposit_slot)(sp)
    ld      t0, LIST_COUNT(s10)
    slli    t0, t0, 3
    add     t0, s10, t0
    addi    t0, t0, LIST_FIXED
    sd      t0, (L + 16)(sp)                # the end of the list
    addi    s10, s10, LIST_FIXED
5:  ld      t0, (L + 16)(sp)
    bgeu    s10, t0, 55f
    ld      t1, 0(s10)                      # for index in pre_activation
    addi    s10, s10, 8
    PART    t2, t3, s5, BeaconState_balances
    slli    t4, t1, 3
    add     t4, t2, t4
    ld      t5, 0(t4)
    sd      zero, 0(t4)                     # post.balances[index] = 0
    sd      t5, (L + 32 + PendingDeposit_amount)(sp)
    PART    t2, t3, s5, BeaconState_validators
    slli    t4, t1, 7
    add     a1, t2, t4
    sd      zero, Validator_effective_balance(a1)
    li      t0, -1
    sd      t0, Validator_activation_eligibility_epoch(a1)
    addi    a0, sp, (L + 32)                # PendingDeposit(validator.pubkey, validator.withdrawal_credentials, balance, ...)
    li      a2, PendingDeposit_amount
    call    lantern_copy
    mv      a0, s5
    addi    a1, sp, (L + 32)
    call    append_pending_deposit
    bnez    a0, 7f
    j       5b
55: li      s10, 0
56: bgeu    s10, s7, 8f                     # queue_excess_active_balance for each compounding validator
    PART    t2, t3, s5, BeaconState_validators
    slli    t4, s10, 7
    add     t4, t2, t4
    lbu     t5, Validator_withdrawal_credentials(t4)
    li      t6, COMPOUNDING_WITHDRAWAL_PREFIX
    bne     t5, t6, 57f
    sd      s10, (L + 24)(sp)
    mv      a0, s5
    addi    a1, sp, (L + 24)
    call    lantern_queue_excess_active_balance
    bnez    a0, 7f
57: addi    s10, s10, 1
    j       56b
.elseif FORK == FORK_FULU
    sd      s9, 0(s4)
    mv      a0, s5                          # post.proposer_lookahead = initialize_proposer_lookahead(post)
    mv      a1, s4
    ADDQ    a2, s5, BeaconState_proposer_lookahead
    call    lantern_initialize_proposer_lookahead
    bnez    a0, 7f
.endif
8:  li      a0, LANTERN_OK
7:  sd      s9, 0(s4)
    LEAVE 240
6:  li      a0, LANTERN_INVALID_OVERFLOW
    j       7b
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 240
SPEC_END \name
.endm

.if FORK == FORK_ALTAIR
UPGRADE_FUNCTION upgrade_to_altair, CONFIG_ALTAIR_FORK_VERSION
.elseif FORK == FORK_BELLATRIX
UPGRADE_FUNCTION upgrade_to_bellatrix, CONFIG_BELLATRIX_FORK_VERSION
.elseif FORK == FORK_CAPELLA
UPGRADE_FUNCTION upgrade_to_capella, CONFIG_CAPELLA_FORK_VERSION
.elseif FORK == FORK_DENEB
UPGRADE_FUNCTION upgrade_to_deneb, CONFIG_DENEB_FORK_VERSION
.elseif FORK == FORK_ELECTRA
UPGRADE_FUNCTION upgrade_to_electra, CONFIG_ELECTRA_FORK_VERSION
.elseif FORK == FORK_FULU
UPGRADE_FUNCTION upgrade_to_fulu, CONFIG_FULU_FORK_VERSION
.endif
