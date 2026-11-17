/*
 * The block steps, the block, slots and the state transition, ARM64.
 * Requirements: docs/reference/block-processing.md and docs/reference/state-transition.md.
 */

/* ---------------------------------------------------------------- RANDAO and eth1 data */

/*
 * x19 state, x20 body, x21 config, x22 scratch, x23 result, x24 proposer.
 * Locals: L epoch, L+8 proposer index, L+16 domain type, L+24 domain (32),
 * L+56 signing root as a ByteList (56), L+112 sha256(reveal), L+144 mix.
 */
SPEC_FUNCTION process_randao
    ENTER 176
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
.if FORK >= FORK_FULU
    NEED_SCRATCH x22, x19, 0, 9f
.else
    NEED_SCRATCH x22, x19, 2, 9f                /* get_beacon_proposer_index takes S(2) */
.endif
    str     xzr, [x23]
    ldr     x24, [x22]
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    mov     x0, x19
.if FORK >= FORK_FULU
    add     x1, sp, #(L + 8)
    bl      lantern_get_beacon_proposer_index
.else
    mov     x1, x22
    add     x2, sp, #(L + 8)
    bl      lantern_get_beacon_proposer_index
    str     x24, [x22]
    cbz     x0, 1f
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    7f
    b       6f
1:
.endif
    ldr     x9, [sp, #(L + 8)]
    PART    x24, x10, x19, BeaconState_validators
    cmp     x9, x10
    mov     x0, #LANTERN_INVALID_VALIDATOR_INDEX
    b.hs    6f
    add     x24, x24, x9, lsl #7
    mov     w9, #DOMAIN_RANDAO              /* signing_root = compute_signing_root(epoch, get_domain(state, DOMAIN_RANDAO)) */
    str     w9, [sp, #(L + 16)]
    mov     x0, x19
    add     x1, sp, #(L + 16)
    add     x2, sp, #L
    mov     x3, x22
    add     x4, sp, #(L + 24)
    bl      lantern_get_domain
    cbnz    x0, 7f
    ADDRESS x0, lantern_type_Uint64
    add     x1, sp, #L
    add     x2, sp, #(L + 24)
    mov     x3, x22
    add     x4, sp, #(L + 80)
    bl      lantern_compute_signing_root
    cbnz    x0, 7f
    add     x0, x24, #Validator_pubkey      /* assert bls.Verify(proposer.pubkey, signing_root, body.randao_reveal) */
    add     x1, x20, #BeaconBlockBody_randao_reveal
    add     x2, sp, #(L + 56)
    mov     x3, x22
    bl      verify_root_signature
    cbnz    x0, 7f
    mov     x0, #LANTERN_INVALID_RANDAO_REVEAL
    cbz     x1, 6f
    add     x0, x20, #BeaconBlockBody_randao_reveal     /* mix = xor(get_randao_mix(state, epoch), sha256(randao_reveal)) */
    mov     x1, #96
    add     x2, sp, #(L + 112)
    bl      sha256_short
    mov     x0, x19
    add     x1, sp, #L
    add     x2, sp, #(L + 144)
    bl      lantern_get_randao_mix
    ldr     x9, [sp, #L]
    and     x9, x9, #(EPOCHS_PER_HISTORICAL_VECTOR - 1)
    ADDQ    x2, x19, BeaconState_randao_mixes
    add     x2, x2, x9, lsl #5
    add     x0, sp, #(L + 144)
    add     x1, sp, #(L + 112)
    bl      lantern_xor
    mov     x0, #LANTERN_OK
7:  LEAVE 176
6:  str     x0, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 176
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 176
SPEC_END process_randao

/* x19 state, x20 body, x21 result. */
SPEC_FUNCTION process_eth1_data
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x4
    LDQ     x9, x19, BeaconState_eth1_data_votes
    LDQ     x10, x19, BeaconState_eth1_data_votes + 8
    LDQ     x11, x19, BeaconState_validators
    sub     x11, x11, x9
    add     x12, x10, #1
    mov     x13, #Eth1Data__mem
    mul     x12, x12, x13
    cmp     x12, x11
    b.hi    9f
    str     xzr, [x21]
    add     x14, x10, #1                    /* state.eth1_data_votes.append(body.eth1_data) */
    STQ     x14, x19, BeaconState_eth1_data_votes + 8
    madd    x0, x10, x13, x9
    add     x0, x19, x0
    add     x1, x20, #BeaconBlockBody_eth1_data
    mov     x2, #Eth1Data__mem
    bl      lantern_copy
    PART    x9, x10, x19, BeaconState_eth1_data_votes   /* state.eth1_data_votes.count(body.eth1_data) */
    add     x11, x20, #BeaconBlockBody_eth1_data
    mov     x12, #0
1:  cbz     x10, 4f
    mov     x13, #0
2:  ldr     x14, [x9, x13]
    ldr     x15, [x11, x13]
    cmp     x14, x15
    b.ne    3f
    add     x13, x13, #8
    cmp     x13, #Eth1Data__mem
    b.lo    2b
    add     x12, x12, #1
3:  add     x9, x9, #Eth1Data__mem
    sub     x10, x10, #1
    b       1b
4:  lsl     x12, x12, #1
    MOVQ    x13, EPOCHS_PER_ETH1_VOTING_PERIOD * SLOTS_PER_EPOCH
    cmp     x12, x13
    b.ls    8f
    ADDQ    x0, x19, BeaconState_eth1_data  /* state.eth1_data = body.eth1_data */
    add     x1, x20, #BeaconBlockBody_eth1_data
    mov     x2, #Eth1Data__mem
    bl      lantern_copy
8:  mov     x0, #LANTERN_OK
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END process_eth1_data

.if Eth1Data__mem != 72
.error "lantern_process_eth1_data compares Eth1Data 8 bytes at a time"
.endif

/* ---------------------------------------------------------------- Operations */

/* Call fn(state, entry, config, scratch, result) for each entry of a list of fixed size entries. */
.macro FOR_FIXED value, ref, stride, fn
    PART    x25, x26, \value, \ref
91: cbz     x26, 92f
    str     x24, [x22]
    mov     x0, x19
    mov     x1, x25
    mov     x2, x21
    mov     x3, x22
    mov     x4, x23
    bl      \fn
    cbnz    x0, 7f
    ldr     x9, [x23]
    cbnz    x9, 8f
    MOVQ    x9, \stride
    add     x25, x25, x9
    sub     x26, x26, #1
    b       91b
92:
.endm

/* The same for a list of nested values: each starts with its size. */
.macro FOR_VARIABLE value, ref, fn
    PART    x25, x26, \value, \ref
91: cbz     x26, 92f
    str     x24, [x22]
    mov     x0, x19
    mov     x1, x25
    mov     x2, x21
    mov     x3, x22
    mov     x4, x23
    bl      \fn
    cbnz    x0, 7f
    ldr     x9, [x23]
    cbnz    x9, 8f
    ldr     x9, [x25]
    add     x25, x25, x9
    sub     x26, x26, #1
    b       91b
92:
.endm

/* x19 state, x20 body, x21 config, x22 scratch, x23 result, x24 scratch size, x25 entry, x26 left, x27 requests. */
SPEC_FUNCTION process_operations
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x24, [x22]
    str     xzr, [x23]
.if FORK >= FORK_FULU
    LDQ     x9, x20, BeaconBlockBody_deposits + 8   /* assert len(body.deposits) == 0 */
    cbz     x9, 1f
.elseif FORK == FORK_ELECTRA
    LDQ     x9, x19, BeaconState_eth1_data + Eth1Data_deposit_count
    LDQ     x10, x19, BeaconState_deposit_requests_start_index
    cmp     x9, x10
    csel    x9, x9, x10, lo                 /* eth1_deposit_index_limit */
    LDQ     x10, x19, BeaconState_eth1_deposit_index
    subs    x9, x9, x10
    csel    x9, x9, xzr, hi                 /* limit - eth1_deposit_index while below the limit, else 0 */
    mov     x10, #MAX_DEPOSITS
    cmp     x9, x10
    csel    x9, x9, x10, lo
    LDQ     x10, x20, BeaconBlockBody_deposits + 8   /* assert len(body.deposits) == that */
    cmp     x10, x9
    b.eq    1f
.else
    LDQ     x9, x19, BeaconState_eth1_data + Eth1Data_deposit_count
    LDQ     x10, x19, BeaconState_eth1_deposit_index
    subs    x9, x9, x10                     /* state.eth1_data.deposit_count - state.eth1_deposit_index */
    mov     x11, #LANTERN_INVALID_OVERFLOW
    b.lo    2f
    mov     x10, #MAX_DEPOSITS
    cmp     x9, x10
    csel    x9, x9, x10, lo
    LDQ     x10, x20, BeaconBlockBody_deposits + 8   /* assert len(body.deposits) == min(MAX_DEPOSITS, ...) */
    cmp     x10, x9
    b.eq    1f
.endif
    mov     x11, #LANTERN_INVALID_DEPOSITS
2:  str     x11, [x23]
    b       8f
1:  FOR_FIXED x20, BeaconBlockBody_proposer_slashings, ProposerSlashing__mem, lantern_process_proposer_slashing
    FOR_VARIABLE x20, BeaconBlockBody_attester_slashings, lantern_process_attester_slashing
    FOR_VARIABLE x20, BeaconBlockBody_attestations, lantern_process_attestation
.if FORK < FORK_FULU
    FOR_FIXED x20, BeaconBlockBody_deposits, Deposit__mem, lantern_process_deposit
.endif
    FOR_FIXED x20, BeaconBlockBody_voluntary_exits, SignedVoluntaryExit__mem, lantern_process_voluntary_exit
.if FORK >= FORK_CAPELLA
    FOR_FIXED x20, BeaconBlockBody_bls_to_execution_changes, SignedBLSToExecutionChange__mem, lantern_process_bls_to_execution_change
.endif
.if FORK >= FORK_ELECTRA
    PART    x27, x9, x20, BeaconBlockBody_execution_requests
    FOR_FIXED x27, ExecutionRequests_deposits, DepositRequest__mem, lantern_process_deposit_request
    FOR_FIXED x27, ExecutionRequests_withdrawals, WithdrawalRequest__mem, lantern_process_withdrawal_request
    FOR_FIXED x27, ExecutionRequests_consolidations, ConsolidationRequest__mem, lantern_process_consolidation_request
.endif
8:  mov     x0, #LANTERN_OK
7:  LEAVE 16
SPEC_END process_operations

/* ---------------------------------------------------------------- The block */

/* x9 = free entries of one list of state x0: (next part offset - offset) // stride - count. Uses x10-x13, x16. */
.macro FREE ref, next, stride
    LDQ     x10, x0, \ref
    LDQ     x11, x0, (\ref) + 8
    LDQ     x12, x0, \next
    sub     x12, x12, x10
    mov     x13, #\stride
    udiv    x12, x12, x13
    sub     x9, x12, x11
.endm

.if FORK >= FORK_ELECTRA
/*
 * L0: x0 = LANTERN_OK when state x0 has room for the appends of the execution requests of
 * block body x1 and x6 more pending deposits, else LANTERN_BUFFER_TOO_SMALL. A leaf.
 */
LOCAL_FUNCTION requests_room
    UNWIND_END_PROLOGUE
    PART    x2, x3, x1, BeaconBlockBody_execution_requests
    LDQ     x3, x2, ExecutionRequests_deposits + 8
    LDQ     x4, x2, ExecutionRequests_withdrawals + 8
    LDQ     x5, x2, ExecutionRequests_consolidations + 8
    FREE    BeaconState_eth1_data_votes, BeaconState_validators, Eth1Data__mem
    cmp     x9, #1
    b.lt    9f
    FREE    BeaconState_pending_deposits, BeaconState_pending_partial_withdrawals, PendingDeposit__mem
    add     x6, x6, x3                      /* deposit requests, and the excess of each switch to compounding */
    add     x6, x6, x5
    cmp     x9, x6
    b.lt    9f
    FREE    BeaconState_pending_partial_withdrawals, BeaconState_pending_consolidations, PendingPartialWithdrawal__mem
    cmp     x9, x4
    b.lt    9f
    LDQ     x10, x0, BeaconState_pending_consolidations     /* the last part ends at the value's end */
    LDQ     x11, x0, BeaconState_pending_consolidations + 8
    ldr     x12, [x0]
    sub     x12, x12, x10
    lsr     x12, x12, #4
    sub     x9, x12, x11
    cmp     x9, x5
    b.lt    9f
    mov     x0, #LANTERN_OK
    ret
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    ret
END_FUNCTION requests_room

.if FORK == FORK_ELECTRA
/*
 * L0: x0 = LANTERN_OK when state x0 has room for the appends of block body x1, else
 * LANTERN_BUFFER_TOO_SMALL: a validator and a pending deposit for each deposit, and the
 * appends of the execution requests. x19 state, x20 body.
 */
LOCAL_FUNCTION block_room
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    bl      validator_room
    LDQ     x6, x20, BeaconBlockBody_deposits + 8
    cmp     x0, x6
    b.lo    9f
    mov     x0, x19
    mov     x1, x20
    bl      requests_room
    LEAVE 0
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION block_room
.else
/* L0: requests_room with no deposits. */
LOCAL_FUNCTION block_room
    UNWIND_END_PROLOGUE
    mov     x6, #0
    b       requests_room
END_FUNCTION block_room
.endif
.else
.if FORK == FORK_PHASE0
/* x9 = the free bytes of a list of nested values of state x0: its end x12 - its start - its entries' sizes. Uses x10, x11, x13. */
.macro FREE_NESTED ref
    LDQ     x10, x0, \ref
    LDQ     x11, x0, (\ref) + 8
    add     x13, x0, x10
    sub     x9, x12, x10
91: cbz     x11, 92f
    ldr     x10, [x13]
    sub     x9, x9, x10
    add     x13, x13, x10
    sub     x11, x11, #1
    b       91b
92:
.endm
.endif

/*
 * L0: x0 = LANTERN_OK when state x0 has room for the appends of block body x1, else
 * LANTERN_BUFFER_TOO_SMALL: an eth1 data vote, a validator for each deposit and, in phase0,
 * a PendingAttestation for each attestation in each epoch's list.
 * x19 state, x20 body.
 */
LOCAL_FUNCTION block_room
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    FREE    BeaconState_eth1_data_votes, BeaconState_validators, Eth1Data__mem
    cmp     x9, #1
    b.lt    9f
    mov     x0, x19
    bl      validator_room
    LDQ     x9, x20, BeaconBlockBody_deposits + 8
    cmp     x0, x9
    b.lo    9f
.if FORK == FORK_PHASE0
    LDQ     x9, x20, BeaconBlockBody_attestations + 8
    MOVQ    x10, PENDING_ATTESTATION_ROOM
    mul     x14, x9, x10                    /* the bytes the attestations may add to one list */
    mov     x0, x19
    LDQ     x12, x0, BeaconState_current_epoch_attestations
    FREE_NESTED BeaconState_previous_epoch_attestations
    cmp     x9, x14
    b.lo    9f
    ldr     x12, [x0]
    FREE_NESTED BeaconState_current_epoch_attestations
    cmp     x9, x14
    b.lo    9f
.endif
    mov     x0, #LANTERN_OK
    LEAVE 0
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION block_room
.endif

/*
 * L0: x0 = the scratch that lantern_process_block needs for body x1, with x2 validators.
 * A leaf.
 */
LOCAL_FUNCTION block_scratch
    UNWIND_END_PROLOGUE
    lsl     x9, x2, #3
    add     x9, x9, #LIST_FIXED             /* L(n) */
    mov     x10, #10                        /* attestations: S(10) + ATTEST_EXTRA */
    mul     x10, x9, x10
    MOVQ    x11, LANTERN_SCRATCH_FIXED + ATTEST_EXTRA
    add     x10, x10, x11
.if FORK >= FORK_ALTAIR
    MOVQ    x11, LANTERN_SCRATCH_FIXED + SYNC_AGG_EXTRA      /* sync aggregate: S(1) + SYNC_AGG_EXTRA */
    add     x11, x11, x9
    cmp     x11, x10
    csel    x10, x11, x10, hi
.endif
.if FORK >= FORK_BELLATRIX
    PART    x12, x13, x1, BeaconBlockBody_execution_payload /* the payload: its header and transactions */
    TX_BYTES x13, x12, x14
    MOVQ    x11, LANTERN_SCRATCH_FIXED + HEADER_ROOM + 24 + PAYLOAD_WLIST_BYTES
    add     x11, x11, x13
    cmp     x11, x10
    csel    x10, x11, x10, hi
.endif
    mov     x0, x10
    ret
END_FUNCTION block_scratch

/* One block step: stop at a failed status or a failed check. */
.macro BLOCK_STEP
    cbnz    x0, 7f
    ldr     x9, [x24]
    cbnz    x9, 8f
.endm

/* x19 state, x20 block, x21 execution_valid, x22 config, x23 scratch, x24 result, x25 body, x26 scratch size. */
SPEC_FUNCTION process_block
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    PART    x25, x9, x20, BeaconBlock_body
    mov     x0, x19
    mov     x1, x25
    bl      block_room
    cbnz    x0, 7f
    mov     x1, x25
    LDQ     x2, x19, BeaconState_validators + 8
    bl      block_scratch
    ldr     x26, [x23]
    cmp     x26, x0
    b.lo    9f
    str     xzr, [x24]
    mov     x0, x19
    mov     x1, x20
    mov     x2, x22
    mov     x3, x23
    mov     x4, x24
    bl      lantern_process_block_header
    BLOCK_STEP
.if FORK >= FORK_CAPELLA
    str     x26, [x23]
    mov     x0, x19
    PART    x1, x9, x25, BeaconBlockBody_execution_payload
    mov     x2, x22
    mov     x3, x23
    mov     x4, x24
    bl      lantern_process_withdrawals
    BLOCK_STEP
    str     x26, [x23]
    mov     x0, x19
    mov     x1, x25
    mov     x2, x21
    mov     x3, x22
    mov     x4, x23
    mov     x5, x24
    bl      lantern_process_execution_payload
    BLOCK_STEP
.elseif FORK == FORK_BELLATRIX
    mov     x0, x19                         /* if is_execution_enabled(state, block.body): */
    mov     x1, x25
    add     x2, sp, #L
    bl      lantern_is_execution_enabled
    ldr     x9, [sp, #L]
    cbz     x9, 1f
    str     x26, [x23]
    mov     x0, x19
    mov     x1, x25
    mov     x2, x21
    mov     x3, x22
    mov     x4, x23
    mov     x5, x24
    bl      lantern_process_execution_payload
    BLOCK_STEP
1:
.endif
    str     x26, [x23]
    mov     x0, x19
    mov     x1, x25
    mov     x2, x22
    mov     x3, x23
    mov     x4, x24
    bl      lantern_process_randao
    BLOCK_STEP
    str     x26, [x23]
    mov     x0, x19
    mov     x1, x25
    mov     x2, x22
    mov     x3, x23
    mov     x4, x24
    bl      lantern_process_eth1_data
    BLOCK_STEP
    str     x26, [x23]
    mov     x0, x19
    mov     x1, x25
    mov     x2, x22
    mov     x3, x23
    mov     x4, x24
    bl      lantern_process_operations
    BLOCK_STEP
.if FORK >= FORK_ALTAIR
    str     x26, [x23]
    mov     x0, x19
    add     x1, x25, #BeaconBlockBody_sync_aggregate
    mov     x2, x22
    mov     x3, x23
    mov     x4, x24
    bl      lantern_process_sync_aggregate
    BLOCK_STEP
.endif
8:  mov     x0, #LANTERN_OK
7:  LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END process_block

/* ---------------------------------------------------------------- Slots */

/* x19 state, x20 scratch, x21 slot index. Locals: L the state root, L+32 the header root. */
SPEC_FUNCTION process_slot
    ENTER 64
    mov     x19, x0
    mov     x20, x1
    LDQ     x21, x19, BeaconState_slot
    and     x21, x21, #(SLOTS_PER_HISTORICAL_ROOT - 1)
    ADDRESS x0, lantern_type_BeaconState    /* previous_state_root = hash_tree_root(state) */
    mov     x1, x19
    mov     x2, x20
    add     x3, sp, #L
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    ADDQ    x9, x19, BeaconState_state_roots
    add     x9, x9, x21, lsl #5
    add     x10, sp, #L
    COPY32  x9, x10
    ADDQ    x9, x19, BeaconState_latest_block_header + BeaconBlockHeader_state_root
    ldp     x10, x11, [x9]
    ldp     x12, x13, [x9, #16]
    orr     x10, x10, x11
    orr     x12, x12, x13
    orr     x10, x10, x12
    cbnz    x10, 1f
    add     x10, sp, #L                     /* the latest header's state root, when it is zero */
    COPY32  x9, x10
1:  ADDRESS x0, lantern_type_BeaconBlockHeader  /* previous_block_root = hash_tree_root(state.latest_block_header) */
    ADDQ    x1, x19, BeaconState_latest_block_header
    mov     x2, x20
    add     x3, sp, #(L + 32)
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    ADDQ    x9, x19, BeaconState_block_roots
    add     x9, x9, x21, lsl #5
    add     x10, sp, #(L + 32)
    COPY32  x9, x10
    mov     x0, #LANTERN_OK
7:  LEAVE 64
SPEC_END process_slot

/*
 * L0: x0 = LANTERN_OK when state x0 has the room and scratch x2 the bytes to reach slot x1
 * (a value), plus x3 more scratch bytes; else LANTERN_BUFFER_TOO_SMALL. Also x1 = the epochs
 * crossed. A leaf.
 */
LOCAL_FUNCTION slots_room
    UNWIND_END_PROLOGUE
    LDQ     x4, x0, BeaconState_slot
    lsr     x5, x1, #LOG2_SLOTS_PER_EPOCH
    lsr     x6, x4, #LOG2_SLOTS_PER_EPOCH
    subs    x5, x5, x6                      /* epochs crossed */
    csel    x5, x5, xzr, hs
.if FORK >= FORK_ELECTRA
    mov     x6, #MAX_PENDING_DEPOSITS_PER_EPOCH     /* room for the validators those epochs may add */
    umulh   x7, x5, x6
    cbnz    x7, 9f
    mul     x7, x5, x6
    mov     x9, #-1
    VALIDATOR_LISTS LIST_ROOM
    cmp     x9, x7
    b.lo    9f
.else
    mov     x7, #0                          /* epochs add no validators */
.endif
.if FORK == FORK_PHASE0
    cbz     x5, 4f                          /* the current epoch's attestations move to the previous list once */
    LDQ     x10, x0, BeaconState_current_epoch_attestations
    LDQ     x11, x0, BeaconState_current_epoch_attestations + 8
    add     x12, x0, x10
    mov     x13, #0
2:  cbz     x11, 3f
    ldr     x14, [x12]
    add     x13, x13, x14
    add     x12, x12, x14
    sub     x11, x11, #1
    b       2b
3:  LDQ     x11, x0, BeaconState_previous_epoch_attestations
    sub     x10, x10, x11
    cmp     x13, x10
    b.hi    9f
4:
.endif
    lsr     x8, x1, #(LOG2_SLOTS_PER_EPOCH)         /* and for a historical root or summary per batch boundary */
    lsr     x9, x4, #(LOG2_SLOTS_PER_EPOCH)
    mov     x10, #(SLOTS_PER_HISTORICAL_ROOT / SLOTS_PER_EPOCH)
    udiv    x8, x8, x10
    udiv    x9, x9, x10
    subs    x8, x8, x9                      /* none when the slot is before the state's batch */
    csel    x8, x8, xzr, hs
.if FORK >= FORK_CAPELLA
    LDQ     x10, x0, BeaconState_historical_summaries
    LDQ     x11, x0, BeaconState_historical_summaries + 8
.if FORK >= FORK_ELECTRA
    LDQ     x12, x0, BeaconState_pending_deposits
.else
    ldr     x12, [x0]                       /* the last part ends at the end of the value */
.endif
    sub     x12, x12, x10
    lsr     x12, x12, #6
.else
    LDQ     x10, x0, BeaconState_historical_roots
    LDQ     x11, x0, BeaconState_historical_roots + 8
    LDQ     x12, x0, BeaconState_eth1_data_votes
    sub     x12, x12, x10
    lsr     x12, x12, #5
.endif
    sub     x12, x12, x11
    cmp     x12, x8
    b.lo    9f
    LDQ     x9, x0, BeaconState_validators + 8      /* scratch: process_epoch with every validator the epochs may add */
    add     x9, x9, x7
    lsl     x9, x9, #3
    add     x9, x9, #LIST_FIXED
    mov     x10, #EPOCH_LISTS
    mul     x9, x9, x10
    MOVQ    x10, LANTERN_SCRATCH_FIXED + EPOCH_EXTRA
    add     x9, x9, x10
    cmp     x3, x9
    csel    x9, x3, x9, hi
    ldr     x10, [x2]
    cmp     x10, x9
    b.lo    9f
    mov     x1, x5
    mov     x0, #LANTERN_OK
    ret
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    ret
END_FUNCTION slots_room

/* x19 state, x20 slot, x21 config, x22 scratch, x23 result, x24 scratch size. */
SPEC_FUNCTION process_slots
    ENTER 16
    mov     x19, x0
    ldr     x20, [x1]
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    str     xzr, [x23]
    LDQ     x9, x19, BeaconState_slot
    cmp     x9, x20                         /* assert state.slot < slot */
    b.lo    1f
    mov     x9, #LANTERN_INVALID_SLOT
    str     x9, [x23]
    b       8f
1:  mov     x0, x19
    mov     x1, x20
    mov     x2, x22
    mov     x3, #0
    bl      slots_room
    cbnz    x0, 7f
    ldr     x24, [x22]
2:  LDQ     x9, x19, BeaconState_slot
    cmp     x9, x20
    b.hs    8f
    str     x24, [x22]
    mov     x0, x19
    mov     x1, x22
    bl      lantern_process_slot
    cbnz    x0, 7f
    LDQ     x9, x19, BeaconState_slot
    add     x9, x9, #1
    tst     x9, #(SLOTS_PER_EPOCH - 1)
    b.ne    3f
    str     x24, [x22]
    mov     x0, x19
    mov     x1, x21
    mov     x2, x22
    mov     x3, x23
    bl      lantern_process_epoch
    cbnz    x0, 7f
    ldr     x9, [x23]
    cbnz    x9, 8f
3:  LDQ     x9, x19, BeaconState_slot
    add     x9, x9, #1
    STQ     x9, x19, BeaconState_slot
    b       2b
8:  mov     x0, #LANTERN_OK
7:  LEAVE 16
SPEC_END process_slots

/* ---------------------------------------------------------------- Blocks and the transition */

/*
 * x19 state, x20 signed block, x21 scratch, x22 out, x23 block, x24 proposer.
 * Locals: L epoch, L+8 domain type, L+16 domain (32), L+48 signing root as a ByteList (56).
 */
SPEC_FUNCTION verify_block_signature
    ENTER 112
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    str     xzr, [x22]
    PART    x23, x9, x20, SignedBeaconBlock_message
    ldr     x9, [x23, #BeaconBlock_proposer_index]
    PART    x24, x10, x19, BeaconState_validators
    cmp     x9, x10
    b.hs    6f
    add     x24, x24, x9, lsl #7
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    mov     w9, #DOMAIN_BEACON_PROPOSER
    str     w9, [sp, #(L + 8)]
    mov     x0, x19
    add     x1, sp, #(L + 8)
    add     x2, sp, #L
    mov     x3, x21
    add     x4, sp, #(L + 16)
    bl      lantern_get_domain
    cbnz    x0, 7f
    ADDRESS x0, lantern_type_BeaconBlock
    mov     x1, x23
    add     x2, sp, #(L + 16)
    mov     x3, x21
    add     x4, sp, #(L + 72)
    bl      lantern_compute_signing_root
    cbnz    x0, 7f
    add     x0, x24, #Validator_pubkey
    add     x1, x20, #SignedBeaconBlock_signature
    add     x2, sp, #(L + 48)
    mov     x3, x21
    bl      verify_root_signature
    cbnz    x0, 7f
    str     x1, [x22]
7:  LEAVE 112
6:  mov     x0, #LANTERN_INVALID_VALIDATOR_INDEX
    LEAVE 112
SPEC_END verify_block_signature

/*
 * x19 state, x20 signed block, x21 options, x22 config, x23 scratch, x24 result, x25 block,
 * x26 scratch size. Locals: L valid, L+8 state root (32).
 */
SPEC_FUNCTION state_transition
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    str     xzr, [x24]
    PART    x25, x9, x20, SignedBeaconBlock_message
    ldr     x26, [x23]
    PART    x1, x9, x25, BeaconBlock_body   /* before any change: room and scratch for the slots and the block */
    mov     x0, x19
    bl      block_room
    cbnz    x0, 7f
    mov     x0, x19                         /* the epochs the slots cross */
    ldr     x1, [x25, #BeaconBlock_slot]
    mov     x2, x23
    mov     x3, #0
    bl      slots_room
    cbnz    x0, 7f
    mov     x9, #MAX_PENDING_DEPOSITS_PER_EPOCH    /* the block's scratch, with every validator they may add */
    LDQ     x2, x19, BeaconState_validators + 8
    madd    x2, x1, x9, x2
    PART    x1, x9, x25, BeaconBlock_body
    bl      block_scratch
    ldr     x9, [x23]
    cmp     x9, x0
    b.lo    9f
    mov     x0, x19                         /* process_slots(state, block.slot) */
    add     x1, x25, #BeaconBlock_slot
    mov     x2, x22
    mov     x3, x23
    mov     x4, x24
    bl      lantern_process_slots
    cbnz    x0, 7f
    ldr     x9, [x24]
    cbnz    x9, 8f
    ldr     x9, [x21]                       /* if validate_result: assert verify_block_signature(state, signed_block) */
    cbz     x9, 1f
    str     x26, [x23]
    mov     x0, x19
    mov     x1, x20
    mov     x2, x23
    add     x3, sp, #L
    bl      lantern_verify_block_signature
    CHECK_STATUS x24, 7f, 8f
    ldr     x9, [sp, #L]
    cbnz    x9, 1f
    mov     x9, #LANTERN_INVALID_BLOCK_SIGNATURE
    str     x9, [x24]
    b       8f
1:  str     x26, [x23]
    mov     x0, x19                         /* process_block(state, block) */
    mov     x1, x25
    add     x2, x21, #8
    mov     x3, x22
    mov     x4, x23
    mov     x5, x24
    bl      lantern_process_block
    cbnz    x0, 7f
    ldr     x9, [x24]
    cbnz    x9, 8f
    ldr     x9, [x21]                       /* if validate_result: assert block.state_root == hash_tree_root(state) */
    cbz     x9, 8f
    str     x26, [x23]
    ADDRESS x0, lantern_type_BeaconState
    mov     x1, x19
    mov     x2, x23
    add     x3, sp, #(L + 8)
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    add     x14, x25, #BeaconBlock_state_root
    add     x15, sp, #(L + 8)
    NE32    x14, x15, 2f
    b       8f
2:  mov     x9, #LANTERN_INVALID_STATE_ROOT
    str     x9, [x24]
8:  mov     x0, #LANTERN_OK
7:  LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END state_transition
