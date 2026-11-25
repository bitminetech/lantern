/*
 * Fork upgrades, ARM64. Requirements: docs/reference/fork-upgrades.md.
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
.set UP_DEPOSITS, 6                 /* electra: room for x26 entries, appended after the parts */

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

/* Copy the fixed field name of the state before x19 to the new state x23. */
.macro UP_COPY_FIELD name
    .if BeaconState_\name\()__mem != PRE_BeaconState_\name\()__mem
    .error "UP_FIXED: a field changes its size"
    .endif
    ADDQ    x0, x23, BeaconState_\name
    ADDQ    x1, x19, PRE_BeaconState_\name
    MOVQ    x2, BeaconState_\name\()__mem
    bl      lantern_copy
.endm

/* x10 = the entries of the new part name. */
.macro UP_COUNT name, how
.if (\how) == UP_COPY
    LDQ     x10, x19, PRE_BeaconState_\name + 8
.elseif (\how) == UP_ZEROS
    LDQ     x10, x19, PRE_BeaconState_validators + 8
.elseif (\how) == UP_DEPOSITS
    mov     x10, x26
.elseif (\how) == UP_EMPTY
    mov     x10, #0
.else
    mov     x10, #1                         /* one header value */
.endif
.endm

/* x9 = the bytes of a part of x10 entries of stride with the room at room of StateRoom x20, rounded up to 8. Uses x13. */
.macro UP_CAPACITY stride, room
.if \stride
    mov     x13, #\stride
    .if (\room) >= 0
    ldr     x9, [x20, #\room]
    add     x9, x9, x10
    .else
    mov     x9, x10
    .endif
    mul     x9, x9, x13
    add     x9, x9, #7
    and     x9, x9, #-8
.else
    MOVQ    x9, HEADER_ROOM
.endif
.endm

.macro UP_SIZE_PART name, stride, room, how
    UP_COUNT \name, \how
    UP_CAPACITY \stride, \room
    add     x24, x24, x9
.endm

/* Write the part name of the new state x23 at cursor x24, from the state before x19, and move the cursor. */
.macro UP_WRITE_PART name, stride, room, how
    UP_COUNT \name, \how
    UP_CAPACITY \stride, \room
    STQ     x24, x23, BeaconState_\name
.if (\how) == UP_DEPOSITS
    STQ     xzr, x23, BeaconState_\name + 8
.else
    STQ     x10, x23, BeaconState_\name + 8
.endif
    add     x0, x23, x24
    add     x24, x24, x9
.if (\how) == UP_COPY
    PART    x1, x11, x19, PRE_BeaconState_\name
    .if \stride
    mov     x13, #\stride
    mul     x2, x10, x13
    .else
    ldr     x2, [x1]                        /* a nested value: its size */
    .endif
    bl      lantern_copy
.elseif (\how) == UP_ZEROS
    mov     x13, #\stride
    mul     x1, x10, x13
    bl      lantern_zero
.elseif (\how) == UP_HEADER_EMPTY
    bl      lantern_upgrade_empty_header
.elseif (\how) == UP_HEADER
    PART    x1, x11, x19, PRE_BeaconState_latest_execution_payload_header
    bl      lantern_upgrade_header
.endif
.endm

.if FORK == FORK_BELLATRIX
/* ExecutionPayloadHeader() at x0. */
LOCAL_FUNCTION lantern_upgrade_empty_header
    FRAME 16
    str     x0, [sp, #16]
    MOVQ    x1, ExecutionPayloadHeader__fixed
    bl      lantern_zero
    ldr     x0, [sp, #16]
    MOVQ    x9, ExecutionPayloadHeader__fixed
    str     x9, [x0]                        /* its size */
    STQ     x9, x0, ExecutionPayloadHeader_extra_data   /* the empty extra_data part, after the fixed fields */
    UNFRAME 16
END_FUNCTION lantern_upgrade_empty_header
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
    ldp     x0, x1, [sp, #16]
    ADDQ    x0, x0, ExecutionPayloadHeader_\name
    ADDQ    x1, x1, PRE_ExecutionPayloadHeader_\name
    MOVQ    x2, ExecutionPayloadHeader_\name\()__mem
    bl      lantern_copy
.endm

/* The header of the fork at x0 from the header x1 of the fork before: its fields and extra_data, the new fields zero. */
LOCAL_FUNCTION lantern_upgrade_header
    FRAME 32
    stp     x0, x1, [sp, #16]
    MOVQ    x1, ExecutionPayloadHeader__fixed
    bl      lantern_zero
    UP_HEADER_FIELDS UP_COPY_HEADER_FIELD
    ldp     x0, x3, [sp, #16]
    PART    x1, x2, x3, PRE_ExecutionPayloadHeader_extra_data
    MOVQ    x9, ExecutionPayloadHeader__fixed
    STQ     x9, x0, ExecutionPayloadHeader_extra_data
    STQ     x2, x0, ExecutionPayloadHeader_extra_data + 8
    add     x10, x9, x2
    add     x10, x10, #7
    and     x10, x10, #-8
    str     x10, [x0]                       /* its size */
    add     x0, x0, x9
    bl      lantern_copy
    UNFRAME 32
END_FUNCTION lantern_upgrade_header
.endif

.if FORK == FORK_ELECTRA
/* L0: x0 = the pending deposits that upgrade_to_electra appends for the state before x0. A leaf; uses x1-x8. */
LOCAL_FUNCTION lantern_upgrade_deposit_count
    UNWIND_END_PROLOGUE
    PART    x1, x2, x0, PRE_BeaconState_validators
    PART    x3, x4, x0, PRE_BeaconState_balances
    mov     x0, #0
    MOVQ    x5, MIN_ACTIVATION_BALANCE
1:  cbz     x2, 3f
    ldr     x6, [x1, #Validator_activation_epoch]
    cmn     x6, #1                          /* activation_epoch == FAR_FUTURE_EPOCH: a pending deposit of its balance */
    b.eq    2f
    ldrb    w6, [x1, #Validator_withdrawal_credentials]
    cmp     w6, #COMPOUNDING_WITHDRAWAL_PREFIX
    b.ne    25f
    ldr     x7, [x3]
    cmp     x7, x5                          /* a compounding validator's excess above MIN_ACTIVATION_BALANCE */
    b.ls    25f
2:  add     x0, x0, #1
25: add     x1, x1, #Validator__mem
    add     x3, x3, #8
    sub     x2, x2, #1
    b       1b
3:  ret
END_FUNCTION lantern_upgrade_deposit_count

/* Flags: b.hi when the key of validator index a is above that of b; the key is (activation_eligibility_epoch, index). Uses x14, x15. */
.macro ELIGIBILITY_CMP a, b
    add     x14, x2, \a, lsl #7
    ldr     x14, [x14, #Validator_activation_eligibility_epoch]
    add     x15, x2, \b, lsl #7
    ldr     x15, [x15, #Validator_activation_eligibility_epoch]
    cmp     x14, x15
    b.ne    95f
    cmp     \a, \b
95:
.endm

/* Sift the entry at root down the heap of entries below end, at x0, by key. Uses x5-x8, x14, x15. */
.macro ELIGIBILITY_SIFT root, end
97: lsl     x5, \root, #1
    add     x5, x5, #1                      /* child = 2 * root + 1 */
    cmp     x5, \end
    b.hs    98f
    ldr     x7, [x0, x5, lsl #3]
    add     x6, x5, #1
    cmp     x6, \end
    b.hs    96f
    ldr     x8, [x0, x6, lsl #3]
    ELIGIBILITY_CMP x8, x7                  /* the larger child */
    b.ls    96f
    mov     x5, x6
    mov     x7, x8
96: ldr     x8, [x0, \root, lsl #3]
    ELIGIBILITY_CMP x8, x7
    b.hs    98f
    str     x7, [x0, \root, lsl #3]
    str     x8, [x0, x5, lsl #3]
    mov     \root, x5
    b       97b
98:
.endm

/* L0: sort the x1 validator indices at x0 by (activation_eligibility_epoch, index) of the validators at x2 (heapsort). A leaf. */
LOCAL_FUNCTION lantern_sort_by_eligibility
    UNWIND_END_PROLOGUE
    cmp     x1, #2
    b.lo    9f
    lsr     x9, x1, #1
1:  cbz     x9, 2f
    sub     x9, x9, #1
    mov     x3, x9
    ELIGIBILITY_SIFT x3, x1
    b       1b
2:  mov     x4, x1
3:  sub     x4, x4, #1
    cbz     x4, 9f
    ldr     x5, [x0]
    ldr     x6, [x0, x4, lsl #3]
    str     x6, [x0]
    str     x5, [x0, x4, lsl #3]
    mov     x3, #0
    ELIGIBILITY_SIFT x3, x4
    b       3b
9:  ret
END_FUNCTION lantern_sort_by_eligibility

.if (Validator_pubkey != PendingDeposit_pubkey) || (Validator_withdrawal_credentials != PendingDeposit_withdrawal_credentials) || (PendingDeposit_amount != 80)
.error "upgrade_to_electra copies the pubkey and credentials of a Validator into a PendingDeposit in one block"
.endif
.endif

.if FORK >= FORK_ALTAIR
/* x19 pre, x20 room, x21 size. */
SPEC_FUNCTION upgrade_size
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
.if FORK == FORK_ELECTRA
    bl      lantern_upgrade_deposit_count
    mov     x26, x0
.endif
    MOVQ    x24, BeaconState__fixed
    UP_PARTS UP_SIZE_PART
    str     x24, [x21]
    mov     x0, #LANTERN_OK
    LEAVE 16
SPEC_END upgrade_size
.endif

.if FORK == FORK_ALTAIR
/*
 * x19 state, x20 pre, x21 scratch, x22 the entry, x23 entries left, x24 committee, x25 flags mask,
 * x26 scratch size, x27 the size callees get. Locals: L flags (FLAGS_BYTES).
 */
SPEC_FUNCTION translate_participation
    ENTER 64
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    NEED_SCRATCH x21, x19, 2, 9f
    ldr     x26, [x21]
    LDQ     x9, x19, BeaconState_validators + 8
    SCRATCH_LIST x24, x21, x26, 0, x9       /* the committee: the last list */
    SCRATCH_GIVE x21, x26, 1, x9
    ldr     x27, [x21]
    PART    x22, x23, x20, PRE_BeaconState_previous_epoch_attestations
1:  cbz     x23, 8f                         /* for attestation in pending_attestations */
    MOVQ    x9, FLAGS_BYTES
    str     x9, [sp, #L]
    mov     x0, x19                         /* participation_flag_indices = get_attestation_participation_flag_indices(state, data, inclusion_delay) */
    ADDQ    x1, x22, PRE_PendingAttestation_data
    ADDQ    x2, x22, PRE_PendingAttestation_inclusion_delay
    add     x3, sp, #L
    bl      lantern_get_attestation_participation_flag_indices
    cbnz    x0, 7f
    mov     x25, #0                         /* the flags as one mask: add_flag of each */
    ldr     x9, [sp, #(L + LIST_COUNT)]
    add     x10, sp, #(L + LIST_FIXED)
2:  cbz     x9, 3f
    ldr     x11, [x10], #8
    mov     x12, #1
    lsl     x12, x12, x11
    orr     x25, x25, x12
    sub     x9, x9, #1
    b       2b
3:  str     x27, [x21]
    mov     x0, x19                         /* committee = get_beacon_committee(state, data.slot, data.index) */
    ADDQ    x1, x22, PRE_PendingAttestation_data + PRE_AttestationData_slot
    ADDQ    x2, x22, PRE_PendingAttestation_data + PRE_AttestationData_index
    mov     x4, x21
    mov     x5, x24
    mov     x3, xzr
    bl      lantern_get_beacon_committee
    cbnz    x0, 7f
    PART    x10, x11, x22, PRE_PendingAttestation_aggregation_bits
    PART    x12, x13, x19, BeaconState_previous_epoch_participation
    ldr     x14, [x24, #LIST_COUNT]
    add     x15, x24, #LIST_FIXED
    mov     x9, #0
4:  cmp     x9, x14                         /* each committee member whose aggregation bit is set */
    b.hs    6f
    cmp     x9, x11
    b.hs    6f
    lsr     x16, x9, #3
    ldrb    w16, [x10, x16]
    and     x17, x9, #7
    lsr     w16, w16, w17
    tbz     w16, #0, 5f
    ldr     x16, [x15, x9, lsl #3]
    ldrb    w17, [x12, x16]
    orr     w17, w17, w25
    strb    w17, [x12, x16]
5:  add     x9, x9, #1
    b       4b
6:  ldr     x9, [x22]                       /* the next nested value */
    add     x22, x22, x9
    sub     x23, x23, #1
    b       1b
8:  mov     x0, #LANTERN_OK
7:  str     x26, [x21]
    LEAVE 64
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
SPEC_END translate_participation
.endif

.if FORK >= FORK_FULU
/* x19 state, x20 scratch, x21 out, x22 scratch size, x23 i. Locals: L epoch. */
SPEC_FUNCTION initialize_proposer_lookahead
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    NEED_SCRATCH x20, x19, 2, 9f
    ldr     x22, [x20]
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    mov     x23, #0
1:  cmp     x23, #(MIN_SEED_LOOKAHEAD + 1)  /* for i in range(MIN_SEED_LOOKAHEAD + 1) */
    b.hs    8f
    str     x22, [x20]
    mov     x0, x19                         /* lookahead.extend(get_beacon_proposer_indices(state, current_epoch + i)) */
    add     x1, sp, #L
    mov     x2, x20
    MOVQ    x9, 8 * SLOTS_PER_EPOCH
    madd    x3, x23, x9, x21
    bl      lantern_get_beacon_proposer_indices
    cbnz    x0, 7f
    ldr     x9, [sp, #L]
    adds    x9, x9, #1
    b.cs    6f
    str     x9, [sp, #L]
    add     x23, x23, #1
    b       1b
8:  mov     x0, #LANTERN_OK
7:  str     x22, [x20]
    LEAVE 16
6:  mov     x0, #LANTERN_INVALID_OVERFLOW
    b       7b
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END initialize_proposer_lookahead
.endif

/*
 * The upgrade of the fork, under its spec name.
 * x19 pre, x20 room, x21 config, x22 scratch, x23 out, x24 cursor, x25 validator count,
 * x26 electra: pending deposits, x27 scratch size, x28 entry.
 * Locals: L size, L+8 epoch, L+16 a number, L+24 index, L+32 PendingDeposit (PendingDeposit__mem).
 */
.macro UPGRADE_FUNCTION name, version
SPEC_FUNCTION \name
    ENTER 240
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x27, [x22]
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #L
    bl      lantern_upgrade_size
    ldr     x9, [sp, #L]
    ldr     x10, [x23]
    cmp     x10, x9
    b.lo    9f
.if FORK == FORK_ALTAIR
    NEED_SCRATCH_B x22, x19, 2, SYNC_COMMITTEE_SCRATCH, 9f
.elseif FORK == FORK_ELECTRA || FORK == FORK_FULU
    NEED_SCRATCH x22, x19, 2, 9f
.endif
    LDQ     x25, x19, PRE_BeaconState_validators + 8
.if FORK == FORK_ELECTRA
    mov     x0, x19
    bl      lantern_upgrade_deposit_count
    mov     x26, x0
.endif
    add     x0, x23, #8                     /* the fixed part, after out's own size: zero, then the shared fields */
    MOVQ    x1, BeaconState__fixed - 8
    bl      lantern_zero
    UP_FIXED UP_COPY_FIELD
    ADDQ    x9, x19, PRE_BeaconState_fork + PRE_Fork_current_version
    ldr     w10, [x9]
    ADDQ    x9, x23, BeaconState_fork       /* fork = Fork(pre.fork.current_version, the fork's version, epoch) */
    str     w10, [x9, #Fork_previous_version]
    ldr     w10, [x21, #\version]
    str     w10, [x9, #Fork_current_version]
    LDQ     x10, x19, PRE_BeaconState_slot
    lsr     x10, x10, #LOG2_SLOTS_PER_EPOCH
    str     x10, [x9, #Fork_epoch]
    str     x10, [sp, #(L + 8)]
    MOVQ    x24, BeaconState__fixed         /* the parts, in field order */
    UP_PARTS UP_WRITE_PART
.if FORK == FORK_ALTAIR
    str     x27, [x22]
    mov     x0, x23                         /* translate_participation(post, pre.previous_epoch_attestations) */
    mov     x1, x19
    mov     x2, x22
    bl      lantern_translate_participation
    cbnz    x0, 7f
    str     x27, [x22]
    mov     x0, x23                         /* post.current_sync_committee = get_next_sync_committee(post) */
    mov     x1, x22
    ADDQ    x2, x23, BeaconState_current_sync_committee
    bl      lantern_get_next_sync_committee
    cbnz    x0, 7f
    str     x27, [x22]
    mov     x0, x23                         /* post.next_sync_committee = get_next_sync_committee(post) */
    mov     x1, x22
    ADDQ    x2, x23, BeaconState_next_sync_committee
    bl      lantern_get_next_sync_committee
    cbnz    x0, 7f
.elseif FORK == FORK_ELECTRA
    add     x0, sp, #(L + 8)                /* earliest_exit_epoch = compute_activation_exit_epoch(epoch) */
    add     x1, sp, #(L + 16)
    bl      lantern_compute_activation_exit_epoch
    cbnz    x0, 7f
    ldr     x10, [sp, #(L + 16)]
    STQ     x10, x23, BeaconState_earliest_consolidation_epoch
    PART    x11, x12, x23, BeaconState_validators
1:  cbz     x12, 2f                         /* max with each exit_epoch other than FAR_FUTURE_EPOCH */
    ldr     x13, [x11, #Validator_exit_epoch]
    add     x11, x11, #Validator__mem
    sub     x12, x12, #1
    cmn     x13, #1
    b.eq    1b
    cmp     x13, x10
    csel    x10, x13, x10, hi
    b       1b
2:  adds    x10, x10, #1                    /* earliest_exit_epoch += 1 */
    b.cs    6f
    STQ     x10, x23, BeaconState_earliest_exit_epoch
    mov     x10, #-1                        /* UNSET_DEPOSIT_REQUESTS_START_INDEX */
    STQ     x10, x23, BeaconState_deposit_requests_start_index
    str     x27, [x22]
    mov     x0, x23                         /* exit_balance_to_consume = get_activation_exit_churn_limit(post) */
    mov     x1, x21
    mov     x2, x22
    add     x3, sp, #(L + 16)
    bl      lantern_get_activation_exit_churn_limit
    cbnz    x0, 7f
    ldr     x10, [sp, #(L + 16)]
    STQ     x10, x23, BeaconState_exit_balance_to_consume
    str     x27, [x22]
    mov     x0, x23                         /* consolidation_balance_to_consume = get_consolidation_churn_limit(post) */
    mov     x1, x21
    mov     x2, x22
    add     x3, sp, #(L + 16)
    bl      lantern_get_consolidation_churn_limit
    cbnz    x0, 7f
    ldr     x10, [sp, #(L + 16)]
    STQ     x10, x23, BeaconState_consolidation_balance_to_consume
    SCRATCH_LIST x28, x22, x27, 0, x25      /* pre_activation: the last list of scratch */
    PART    x11, x12, x23, BeaconState_validators
    add     x13, x28, #LIST_FIXED
    mov     x14, #0
3:  cmp     x14, x12                        /* the validators with activation_epoch FAR_FUTURE_EPOCH, in index order */
    b.hs    4f
    ldr     x15, [x11, #Validator_activation_epoch]
    add     x11, x11, #Validator__mem
    cmn     x15, #1
    b.ne    35f
    str     x14, [x13], #8
35: add     x14, x14, #1
    b       3b
4:  add     x9, x28, #LIST_FIXED
    sub     x13, x13, x9
    lsr     x13, x13, #3
    str     x13, [x28, #LIST_COUNT]
    add     x0, x28, #LIST_FIXED            /* sorted by (activation_eligibility_epoch, index) */
    mov     x1, x13
    PART    x2, x9, x23, BeaconState_validators
    bl      lantern_sort_by_eligibility
    add     x0, sp, #(L + 32 + PendingDeposit_signature)   /* signature: G2_POINT_AT_INFINITY; slot: GENESIS_SLOT */
    mov     x1, #96
    bl      lantern_zero
    mov     w9, #0xc0
    strb    w9, [sp, #(L + 32 + PendingDeposit_signature)]
    str     xzr, [sp, #(L + 32 + PendingDeposit_slot)]
    ldr     x9, [x28, #LIST_COUNT]
    add     x9, x28, x9, lsl #3
    add     x9, x9, #LIST_FIXED
    str     x9, [sp, #(L + 16)]             /* the end of the list */
    add     x28, x28, #LIST_FIXED
5:  ldr     x9, [sp, #(L + 16)]
    cmp     x28, x9
    b.hs    55f
    ldr     x10, [x28], #8                  /* for index in pre_activation */
    PART    x11, x12, x23, BeaconState_balances
    ldr     x13, [x11, x10, lsl #3]
    str     xzr, [x11, x10, lsl #3]         /* post.balances[index] = 0 */
    str     x13, [sp, #(L + 32 + PendingDeposit_amount)]
    PART    x11, x12, x23, BeaconState_validators
    add     x11, x11, x10, lsl #7
    str     xzr, [x11, #Validator_effective_balance]
    mov     x12, #-1
    str     x12, [x11, #Validator_activation_eligibility_epoch]
    add     x0, sp, #(L + 32)               /* PendingDeposit(validator.pubkey, validator.withdrawal_credentials, balance, ...) */
    mov     x1, x11
    mov     x2, #(PendingDeposit_amount)
    bl      lantern_copy
    mov     x0, x23
    add     x1, sp, #(L + 32)
    bl      lantern_append_pending_deposit
    cbnz    x0, 7f
    b       5b
55: mov     x28, #0
56: cmp     x28, x25                        /* queue_excess_active_balance for each compounding validator */
    b.hs    8f
    PART    x11, x12, x23, BeaconState_validators
    add     x11, x11, x28, lsl #7
    ldrb    w12, [x11, #Validator_withdrawal_credentials]
    cmp     w12, #COMPOUNDING_WITHDRAWAL_PREFIX
    b.ne    57f
    str     x28, [sp, #(L + 24)]
    mov     x0, x23
    add     x1, sp, #(L + 24)
    bl      lantern_queue_excess_active_balance
    cbnz    x0, 7f
57: add     x28, x28, #1
    b       56b
.elseif FORK == FORK_FULU
    str     x27, [x22]
    mov     x0, x23                         /* post.proposer_lookahead = initialize_proposer_lookahead(post) */
    mov     x1, x22
    ADDQ    x2, x23, BeaconState_proposer_lookahead
    bl      lantern_initialize_proposer_lookahead
    cbnz    x0, 7f
.endif
8:  mov     x0, #LANTERN_OK
7:  str     x27, [x22]
    LEAVE 240
6:  mov     x0, #LANTERN_INVALID_OVERFLOW
    b       7b
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
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
