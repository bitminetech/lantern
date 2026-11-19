/*
 * The block steps, the block, slots and the state transition, RISC-V.
 * Requirements: docs/reference/block-processing.md and docs/reference/state-transition.md.
 */

/* ---------------------------------------------------------------- RANDAO and eth1 data */

/*
 * s1 state, s2 body, s3 config, s4 scratch, s5 result, s6 proposer.
 * Locals: L epoch, L+8 proposer index, L+16 domain type, L+24 domain (32),
 * L+56 signing root as a ByteList (56), L+112 sha256(reveal), L+144 mix.
 */
SPEC_FUNCTION process_randao
    ENTER 176
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
.if FORK >= FORK_FULU
    NEED_SCRATCH s4, s1, 0, 9f
.else
    NEED_SCRATCH s4, s1, 2, 9f                  # get_beacon_proposer_index takes S(2)
.endif
    sd      zero, 0(s5)
    ld      s6, 0(s4)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    mv      a0, s1
.if FORK >= FORK_FULU
    addi    a1, sp, (L + 8)
    call    lantern_get_beacon_proposer_index
.else
    mv      a1, s4
    addi    a2, sp, (L + 8)
    call    lantern_get_beacon_proposer_index
    sd      s6, 0(s4)
    beqz    a0, 1f
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 7f
    j       6f
1:
.endif
    ld      t0, (L + 8)(sp)
    PART    s6, t1, s1, BeaconState_validators
    li      a0, LANTERN_INVALID_VALIDATOR_INDEX
    bgeu    t0, t1, 6f
    slli    t0, t0, 7
    add     s6, s6, t0
    li      t0, DOMAIN_RANDAO               # signing_root = compute_signing_root(epoch, get_domain(state, DOMAIN_RANDAO))
    sw      t0, (L + 16)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 16)
    addi    a2, sp, L
    mv      a3, s4
    addi    a4, sp, (L + 24)
    call    lantern_get_domain
    bnez    a0, 7f
    ADDRESS a0, lantern_type_Uint64
    addi    a1, sp, L
    addi    a2, sp, (L + 24)
    mv      a3, s4
    addi    a4, sp, (L + 80)
    call    lantern_compute_signing_root
    bnez    a0, 7f
    addi    a0, s6, Validator_pubkey        # assert bls.Verify(proposer.pubkey, signing_root, body.randao_reveal)
    addi    a1, s2, BeaconBlockBody_randao_reveal
    addi    a2, sp, (L + 56)
    mv      a3, s4
    call    verify_root_signature
    bnez    a0, 7f
    li      a0, LANTERN_INVALID_RANDAO_REVEAL
    beqz    a1, 6f
    addi    a0, s2, BeaconBlockBody_randao_reveal   # mix = xor(get_randao_mix(state, epoch), sha256(randao_reveal))
    li      a1, 96
    addi    a2, sp, (L + 112)
    call    sha256_short
    mv      a0, s1
    addi    a1, sp, L
    addi    a2, sp, (L + 144)
    call    lantern_get_randao_mix
    ld      t0, L(sp)
    li      t1, (EPOCHS_PER_HISTORICAL_VECTOR - 1)
    and     t0, t0, t1
    ADDQ    a2, s1, BeaconState_randao_mixes
    slli    t0, t0, 5
    add     a2, a2, t0
    addi    a0, sp, (L + 144)
    addi    a1, sp, (L + 112)
    call    lantern_xor
    li      a0, LANTERN_OK
7:  LEAVE 176
6:  sd      a0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 176
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 176
SPEC_END process_randao

/* s1 state, s2 body, s3 result. */
SPEC_FUNCTION process_eth1_data
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a4
    LDQ     t0, s1, BeaconState_eth1_data_votes
    LDQ     t1, s1, BeaconState_eth1_data_votes + 8
    LDQ     t2, s1, BeaconState_validators
    sub     t2, t2, t0
    addi    t3, t1, 1
    li      t4, Eth1Data__mem
    mul     t3, t3, t4
    bgtu    t3, t2, 9f
    sd      zero, 0(s3)
    addi    t3, t1, 1                       # state.eth1_data_votes.append(body.eth1_data)
    STQ     t3, s1, BeaconState_eth1_data_votes + 8
    mul     a0, t1, t4
    add     a0, a0, t0
    add     a0, s1, a0
    addi    a1, s2, BeaconBlockBody_eth1_data
    li      a2, Eth1Data__mem
    call    lantern_copy
    PART    t0, t1, s1, BeaconState_eth1_data_votes     # state.eth1_data_votes.count(body.eth1_data)
    addi    t2, s2, BeaconBlockBody_eth1_data
    li      t3, 0
    li      t6, Eth1Data__mem
1:  beqz    t1, 4f
    li      t4, 0
2:  add     t5, t0, t4
    ld      t5, 0(t5)
    add     a3, t2, t4
    ld      a3, 0(a3)
    bne     t5, a3, 3f
    addi    t4, t4, 8
    bltu    t4, t6, 2b
    addi    t3, t3, 1
3:  addi    t0, t0, Eth1Data__mem
    addi    t1, t1, -1
    j       1b
4:  slli    t3, t3, 1
    li      t4, EPOCHS_PER_ETH1_VOTING_PERIOD * SLOTS_PER_EPOCH
    bleu    t3, t4, 8f
    ADDQ    a0, s1, BeaconState_eth1_data   # state.eth1_data = body.eth1_data
    addi    a1, s2, BeaconBlockBody_eth1_data
    li      a2, Eth1Data__mem
    call    lantern_copy
8:  li      a0, LANTERN_OK
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END process_eth1_data

.if Eth1Data__mem != 72
.error "lantern_process_eth1_data compares Eth1Data 8 bytes at a time"
.endif

/* ---------------------------------------------------------------- Operations */

/* Call fn(state, entry, config, scratch, result) for each entry of a list of fixed size entries. */
.macro FOR_FIXED value, ref, stride, fn
    PART    s7, s8, \value, \ref
91: beqz    s8, 92f
    sd      s6, 0(s4)
    mv      a0, s1
    mv      a1, s7
    mv      a2, s3
    mv      a3, s4
    mv      a4, s5
    call    \fn
    bnez    a0, 7f
    ld      t0, 0(s5)
    bnez    t0, 8f
    li      t0, \stride
    add     s7, s7, t0
    addi    s8, s8, -1
    j       91b
92:
.endm

/* The same for a list of nested values: each starts with its size. */
.macro FOR_VARIABLE value, ref, fn
    PART    s7, s8, \value, \ref
91: beqz    s8, 92f
    sd      s6, 0(s4)
    mv      a0, s1
    mv      a1, s7
    mv      a2, s3
    mv      a3, s4
    mv      a4, s5
    call    \fn
    bnez    a0, 7f
    ld      t0, 0(s5)
    bnez    t0, 8f
    ld      t0, 0(s7)
    add     s7, s7, t0
    addi    s8, s8, -1
    j       91b
92:
.endm

/* s1 state, s2 body, s3 config, s4 scratch, s5 result, s6 scratch size, s7 entry, s8 left, s9 requests. */
SPEC_FUNCTION process_operations
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      s6, 0(s4)
    sd      zero, 0(s5)
.if FORK >= FORK_FULU
    LDQ     t0, s2, BeaconBlockBody_deposits + 8    # assert len(body.deposits) == 0
    beqz    t0, 1f
.elseif FORK == FORK_ELECTRA
    LDQ     t0, s1, BeaconState_eth1_data + Eth1Data_deposit_count
    LDQ     t1, s1, BeaconState_deposit_requests_start_index
    bleu    t0, t1, 0f
    mv      t0, t1                          # eth1_deposit_index_limit
0:  LDQ     t1, s1, BeaconState_eth1_deposit_index
    li      t2, 0                           # limit - eth1_deposit_index while below the limit, else 0
    bleu    t0, t1, 3f
    sub     t2, t0, t1
3:  li      t1, MAX_DEPOSITS
    bleu    t2, t1, 4f
    mv      t2, t1
4:  LDQ     t1, s2, BeaconBlockBody_deposits + 8    # assert len(body.deposits) == that
    beq     t2, t1, 1f
.else
    LDQ     t0, s1, BeaconState_eth1_data + Eth1Data_deposit_count
    LDQ     t1, s1, BeaconState_eth1_deposit_index
    li      t2, LANTERN_INVALID_OVERFLOW
    bltu    t0, t1, 2f
    sub     t0, t0, t1                      # state.eth1_data.deposit_count - state.eth1_deposit_index
    li      t1, MAX_DEPOSITS
    bleu    t0, t1, 0f
    mv      t0, t1
0:  LDQ     t1, s2, BeaconBlockBody_deposits + 8    # assert len(body.deposits) == min(MAX_DEPOSITS, ...)
    beq     t0, t1, 1f
.endif
    li      t2, LANTERN_INVALID_DEPOSITS
2:  sd      t2, 0(s5)
    j       8f
1:  FOR_FIXED s2, BeaconBlockBody_proposer_slashings, ProposerSlashing__mem, lantern_process_proposer_slashing
    FOR_VARIABLE s2, BeaconBlockBody_attester_slashings, lantern_process_attester_slashing
    FOR_VARIABLE s2, BeaconBlockBody_attestations, lantern_process_attestation
.if FORK < FORK_FULU
    FOR_FIXED s2, BeaconBlockBody_deposits, Deposit__mem, lantern_process_deposit
.endif
    FOR_FIXED s2, BeaconBlockBody_voluntary_exits, SignedVoluntaryExit__mem, lantern_process_voluntary_exit
.if FORK >= FORK_CAPELLA
    FOR_FIXED s2, BeaconBlockBody_bls_to_execution_changes, SignedBLSToExecutionChange__mem, lantern_process_bls_to_execution_change
.endif
.if FORK >= FORK_ELECTRA
    PART    s9, t0, s2, BeaconBlockBody_execution_requests
    FOR_FIXED s9, ExecutionRequests_deposits, DepositRequest__mem, lantern_process_deposit_request
    FOR_FIXED s9, ExecutionRequests_withdrawals, WithdrawalRequest__mem, lantern_process_withdrawal_request
    FOR_FIXED s9, ExecutionRequests_consolidations, ConsolidationRequest__mem, lantern_process_consolidation_request
.endif
8:  li      a0, LANTERN_OK
7:  LEAVE 16
SPEC_END process_operations

/* ---------------------------------------------------------------- The block */

/* t0 = free entries of one list of state a0: (next part offset - offset) // stride - count. Uses t1-t3, a7. */
.macro FREE ref, next, stride
    LDQ     t1, a0, \ref
    LDQ     t2, a0, (\ref) + 8
    LDQ     t3, a0, \next
    sub     t3, t3, t1
    li      t1, \stride
    divu    t3, t3, t1
    sub     t0, t3, t2
.endm

.if FORK >= FORK_ELECTRA
/*
 * L0: a0 = LANTERN_OK when state a0 has room for the appends of the execution requests of
 * block body a1 and t4 more pending deposits, else LANTERN_BUFFER_TOO_SMALL. A leaf.
 */
LOCAL_FUNCTION requests_room
    UNWIND_END_PROLOGUE
    PART    a2, a3, a1, BeaconBlockBody_execution_requests
    LDQ     a3, a2, ExecutionRequests_deposits + 8
    LDQ     a4, a2, ExecutionRequests_withdrawals + 8
    LDQ     a5, a2, ExecutionRequests_consolidations + 8
    FREE    BeaconState_eth1_data_votes, BeaconState_validators, Eth1Data__mem
    li      t1, 1
    blt     t0, t1, 9f
    FREE    BeaconState_pending_deposits, BeaconState_pending_partial_withdrawals, PendingDeposit__mem
    add     a6, t4, a3                      # deposit requests, and the excess of each switch to compounding
    add     a6, a6, a5
    blt     t0, a6, 9f
    FREE    BeaconState_pending_partial_withdrawals, BeaconState_pending_consolidations, PendingPartialWithdrawal__mem
    blt     t0, a4, 9f
    LDQ     t1, a0, BeaconState_pending_consolidations      # the last part ends at the value's end
    LDQ     t2, a0, BeaconState_pending_consolidations + 8
    ld      t3, 0(a0)
    sub     t3, t3, t1
    srli    t3, t3, 4
    sub     t0, t3, t2
    blt     t0, a5, 9f
    li      a0, LANTERN_OK
    ret
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    ret
END_FUNCTION requests_room

.if FORK == FORK_ELECTRA
/*
 * L0: a0 = LANTERN_OK when state a0 has room for the appends of block body a1, else
 * LANTERN_BUFFER_TOO_SMALL: a validator and a pending deposit for each deposit, and the
 * appends of the execution requests. s1 state, s2 body.
 */
LOCAL_FUNCTION block_room
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    call    validator_room
    LDQ     t4, s2, BeaconBlockBody_deposits + 8
    bltu    a0, t4, 9f
    mv      a0, s1
    mv      a1, s2
    call    requests_room
    LEAVE 0
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION block_room
.else
/* L0: requests_room with no deposits. */
LOCAL_FUNCTION block_room
    UNWIND_END_PROLOGUE
    li      t4, 0
    j       requests_room
END_FUNCTION block_room
.endif

.else
.if FORK == FORK_PHASE0
/* t0 = the free bytes of a list of nested values of state s1: its end offset t5 - its start - its entries' sizes. Uses t1-t3, a7. */
.macro FREE_NESTED ref
    LDQ     t1, s1, \ref
    LDQ     t2, s1, (\ref) + 8
    sub     t0, t5, t1
    add     t3, s1, t1
91: beqz    t2, 92f
    ld      t1, 0(t3)
    sub     t0, t0, t1
    add     t3, t3, t1
    addi    t2, t2, -1
    j       91b
92:
.endm
.endif

/*
 * L0: a0 = LANTERN_OK when state a0 has room for the appends of block body a1, else
 * LANTERN_BUFFER_TOO_SMALL: an eth1 data vote, a validator for each deposit and, in phase0,
 * a PendingAttestation for each attestation in each epoch's list.
 * s1 state, s2 body, s3 the bytes the attestations may add to one list.
 */
LOCAL_FUNCTION block_room
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    FREE    BeaconState_eth1_data_votes, BeaconState_validators, Eth1Data__mem
    li      t1, 1
    blt     t0, t1, 9f
    mv      a0, s1
    call    validator_room
    LDQ     t0, s2, BeaconBlockBody_deposits + 8
    bltu    a0, t0, 9f
.if FORK == FORK_PHASE0
    LDQ     t0, s2, BeaconBlockBody_attestations + 8
    li      t1, PENDING_ATTESTATION_ROOM
    mul     s3, t0, t1
    LDQ     t5, s1, BeaconState_current_epoch_attestations
    FREE_NESTED BeaconState_previous_epoch_attestations
    bltu    t0, s3, 9f
    ld      t5, 0(s1)
    FREE_NESTED BeaconState_current_epoch_attestations
    bltu    t0, s3, 9f
.endif
    li      a0, LANTERN_OK
    LEAVE 0
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION block_room
.endif

/*
 * L0: a0 = the scratch that lantern_process_block needs for body a1, with a2 validators.
 * A leaf.
 */
LOCAL_FUNCTION block_scratch
    UNWIND_END_PROLOGUE
    slli    t0, a2, 3
    addi    t0, t0, LIST_FIXED              # L(n)
    li      t1, 10                          # attestations: S(10) + ATTEST_EXTRA
    mul     t1, t0, t1
    li      t2, LANTERN_SCRATCH_FIXED + ATTEST_EXTRA
    add     t1, t1, t2
.if FORK >= FORK_ALTAIR
    li      t2, LANTERN_SCRATCH_FIXED + SYNC_AGG_EXTRA     # sync aggregate: S(1) + SYNC_AGG_EXTRA
    add     t2, t2, t0
    bleu    t2, t1, 1f
    mv      t1, t2
1:
.endif
.if FORK >= FORK_BELLATRIX
    PART    t3, t4, a1, BeaconBlockBody_execution_payload  # the payload: its header and transactions
    TX_BYTES t4, t3, t5
    li      t2, LANTERN_SCRATCH_FIXED + HEADER_ROOM + 24 + PAYLOAD_WLIST_BYTES
    add     t2, t2, t4
    bleu    t2, t1, 2f
    mv      t1, t2
2:
.endif
    mv      a0, t1
    ret
END_FUNCTION block_scratch

/* One block step: stop at a failed status or a failed check. */
.macro BLOCK_STEP
    bnez    a0, 7f
    ld      t0, 0(s6)
    bnez    t0, 8f
.endm

/* s1 state, s2 block, s3 execution_valid, s4 config, s5 scratch, s6 result, s7 body, s8 scratch size. */
SPEC_FUNCTION process_block
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    PART    s7, t0, s2, BeaconBlock_body
    mv      a0, s1
    mv      a1, s7
    call    block_room
    bnez    a0, 7f
    mv      a1, s7
    LDQ     a2, s1, BeaconState_validators + 8
    call    block_scratch
    ld      s8, 0(s5)
    bltu    s8, a0, 9f
    sd      zero, 0(s6)
    mv      a0, s1
    mv      a1, s2
    mv      a2, s4
    mv      a3, s5
    mv      a4, s6
    call    lantern_process_block_header
    BLOCK_STEP
.if FORK >= FORK_CAPELLA
    sd      s8, 0(s5)
    mv      a0, s1
    PART    a1, t0, s7, BeaconBlockBody_execution_payload
    mv      a2, s4
    mv      a3, s5
    mv      a4, s6
    call    lantern_process_withdrawals
    BLOCK_STEP
    sd      s8, 0(s5)
    mv      a0, s1
    mv      a1, s7
    mv      a2, s3
    mv      a3, s4
    mv      a4, s5
    mv      a5, s6
    call    lantern_process_execution_payload
    BLOCK_STEP
.elseif FORK == FORK_BELLATRIX
    mv      a0, s1                          # if is_execution_enabled(state, block.body):
    mv      a1, s7
    addi    a2, sp, L
    call    lantern_is_execution_enabled
    ld      t0, L(sp)
    beqz    t0, 1f
    sd      s8, 0(s5)
    mv      a0, s1
    mv      a1, s7
    mv      a2, s3
    mv      a3, s4
    mv      a4, s5
    mv      a5, s6
    call    lantern_process_execution_payload
    BLOCK_STEP
1:
.endif
    sd      s8, 0(s5)
    mv      a0, s1
    mv      a1, s7
    mv      a2, s4
    mv      a3, s5
    mv      a4, s6
    call    lantern_process_randao
    BLOCK_STEP
    sd      s8, 0(s5)
    mv      a0, s1
    mv      a1, s7
    mv      a2, s4
    mv      a3, s5
    mv      a4, s6
    call    lantern_process_eth1_data
    BLOCK_STEP
    sd      s8, 0(s5)
    mv      a0, s1
    mv      a1, s7
    mv      a2, s4
    mv      a3, s5
    mv      a4, s6
    call    lantern_process_operations
    BLOCK_STEP
.if FORK >= FORK_ALTAIR
    sd      s8, 0(s5)
    mv      a0, s1
    ADDQ    a1, s7, BeaconBlockBody_sync_aggregate
    mv      a2, s4
    mv      a3, s5
    mv      a4, s6
    call    lantern_process_sync_aggregate
    BLOCK_STEP
.endif
8:  li      a0, LANTERN_OK
7:  LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END process_block

/* ---------------------------------------------------------------- Slots */

/* s1 state, s2 scratch, s3 slot index. Locals: L the state root, L+32 the header root. */
SPEC_FUNCTION process_slot
    ENTER 64
    mv      s1, a0
    mv      s4, a1
    mv      s2, a2
    LDQ     s3, s1, BeaconState_slot
    li      t0, (SLOTS_PER_HISTORICAL_ROOT - 1)
    and     s3, s3, t0
    mv      a0, s1                          # previous_state_root = hash_tree_root(state)
    ld      a1, CONFIG_STATE_CACHE(s4)
    mv      a2, s2
    addi    a3, sp, L
    call    lantern_state_root
    bnez    a0, 7f
    ADDQ    t0, s1, BeaconState_state_roots
    slli    t1, s3, 5
    add     t0, t0, t1
    addi    t1, sp, L
    COPY32  t0, t1
    ADDQ    t0, s1, BeaconState_latest_block_header + BeaconBlockHeader_state_root
    ld      t1, 0(t0)
    ld      t2, 8(t0)
    or      t1, t1, t2
    ld      t2, 16(t0)
    or      t1, t1, t2
    ld      t2, 24(t0)
    or      t1, t1, t2
    bnez    t1, 1f
    addi    t1, sp, L                       # the latest header's state root, when it is zero
    COPY32  t0, t1
1:  ADDRESS a0, lantern_type_BeaconBlockHeader  # previous_block_root = hash_tree_root(state.latest_block_header)
    ADDQ    a1, s1, BeaconState_latest_block_header
    mv      a2, s2
    addi    a3, sp, (L + 32)
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 7f
    ADDQ    t0, s1, BeaconState_block_roots
    slli    t1, s3, 5
    add     t0, t0, t1
    addi    t1, sp, (L + 32)
    COPY32  t0, t1
    li      a0, LANTERN_OK
7:  LEAVE 64
SPEC_END process_slot

/*
 * L0: a0 = LANTERN_OK when state a0 has the room and scratch a2 the bytes to reach slot a1
 * (a value), plus a3 more scratch bytes; else LANTERN_BUFFER_TOO_SMALL. Also a1 = the epochs
 * crossed. A leaf.
 */
LOCAL_FUNCTION slots_room
    UNWIND_END_PROLOGUE
    LDQ     a4, a0, BeaconState_slot
    srli    a5, a1, LOG2_SLOTS_PER_EPOCH
    srli    a6, a4, LOG2_SLOTS_PER_EPOCH
    li      t5, 0
    bltu    a5, a6, 1f
    sub     t5, a5, a6                      # epochs crossed
1:
.if FORK >= FORK_ELECTRA
    li      a6, MAX_PENDING_DEPOSITS_PER_EPOCH  # room for the validators those epochs may add
    mulhu   t6, t5, a6
    bnez    t6, 9f
    mul     t6, t5, a6
    li      t0, -1
    VALIDATOR_LISTS LIST_ROOM
    bltu    t0, t6, 9f
.else
    li      t6, 0                           # epochs add no validators
.endif
.if FORK == FORK_PHASE0
    beqz    t5, 5f                          # the current epoch's attestations move to the previous list once
    LDQ     t1, a0, BeaconState_current_epoch_attestations
    LDQ     t2, a0, BeaconState_current_epoch_attestations + 8
    add     t3, a0, t1
    li      t0, 0
4:  beqz    t2, 41f
    ld      t4, 0(t3)
    add     t0, t0, t4
    add     t3, t3, t4
    addi    t2, t2, -1
    j       4b
41: LDQ     t2, a0, BeaconState_previous_epoch_attestations
    sub     t1, t1, t2
    bltu    t1, t0, 9f
5:
.endif
    srli    a5, a1, LOG2_SLOTS_PER_EPOCH    # and for a historical root or summary per batch boundary
    srli    a6, a4, LOG2_SLOTS_PER_EPOCH
    li      t1, (SLOTS_PER_HISTORICAL_ROOT / SLOTS_PER_EPOCH)
    divu    a5, a5, t1
    divu    a6, a6, t1
    bgeu    a5, a6, 3f                      # none when the slot is before the state's batch
    mv      a6, a5
3:  sub     a5, a5, a6
.if FORK >= FORK_CAPELLA
    LDQ     t1, a0, BeaconState_historical_summaries
    LDQ     t2, a0, BeaconState_historical_summaries + 8
.if FORK >= FORK_ELECTRA
    LDQ     t3, a0, BeaconState_pending_deposits
.else
    ld      t3, 0(a0)                       # the last part ends at the end of the value
.endif
    sub     t3, t3, t1
    srli    t3, t3, 6
.else
    LDQ     t1, a0, BeaconState_historical_roots
    LDQ     t2, a0, BeaconState_historical_roots + 8
    LDQ     t3, a0, BeaconState_eth1_data_votes
    sub     t3, t3, t1
    srli    t3, t3, 5
.endif
    sub     t3, t3, t2
    bltu    t3, a5, 9f
    LDQ     t1, a0, BeaconState_validators + 8  # scratch: process_epoch with every validator the epochs may add
    add     t1, t1, t6
    slli    t1, t1, 3
    addi    t1, t1, LIST_FIXED
    li      t2, EPOCH_LISTS
    mul     t1, t1, t2
    li      t2, LANTERN_SCRATCH_FIXED + EPOCH_EXTRA
    add     t1, t1, t2
    bleu    a3, t1, 2f
    mv      t1, a3
2:  ld      t2, 0(a2)
    bltu    t2, t1, 9f
    mv      a1, t5
    li      a0, LANTERN_OK
    ret
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    ret
END_FUNCTION slots_room

/* s1 state, s2 slot, s3 config, s4 scratch, s5 result, s6 scratch size. */
SPEC_FUNCTION process_slots
    ENTER 16
    mv      s1, a0
    ld      s2, 0(a1)
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    sd      zero, 0(s5)
    LDQ     t0, s1, BeaconState_slot
    bltu    t0, s2, 1f                      # assert state.slot < slot
    li      t0, LANTERN_INVALID_SLOT
    sd      t0, 0(s5)
    j       8f
1:  mv      a0, s1
    mv      a1, s2
    mv      a2, s4
    li      a3, 0
    call    slots_room
    bnez    a0, 7f
    ld      s6, 0(s4)
2:  LDQ     t0, s1, BeaconState_slot
    bgeu    t0, s2, 8f
    sd      s6, 0(s4)
    mv      a0, s1
    mv      a1, s3
    mv      a2, s4
    call    lantern_process_slot
    bnez    a0, 7f
    LDQ     t0, s1, BeaconState_slot
    addi    t0, t0, 1
    andi    t0, t0, (SLOTS_PER_EPOCH - 1)
    bnez    t0, 3f
    sd      s6, 0(s4)
    mv      a0, s1
    mv      a1, s3
    mv      a2, s4
    mv      a3, s5
    call    lantern_process_epoch
    bnez    a0, 7f
    ld      t0, 0(s5)
    bnez    t0, 8f
3:  LDQ     t0, s1, BeaconState_slot
    addi    t0, t0, 1
    STQ     t0, s1, BeaconState_slot
    j       2b
8:  li      a0, LANTERN_OK
7:  LEAVE 16
SPEC_END process_slots

/* ---------------------------------------------------------------- Blocks and the transition */

/*
 * s1 state, s2 signed block, s3 scratch, s4 out, s5 block, s6 proposer.
 * Locals: L epoch, L+8 domain type, L+16 domain (32), L+48 signing root as a ByteList (56).
 */
SPEC_FUNCTION verify_block_signature
    ENTER 112
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    sd      zero, 0(s4)
    PART    s5, t0, s2, SignedBeaconBlock_message
    ld      t0, BeaconBlock_proposer_index(s5)
    PART    s6, t1, s1, BeaconState_validators
    bgeu    t0, t1, 6f
    slli    t0, t0, 7
    add     s6, s6, t0
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    li      t0, DOMAIN_BEACON_PROPOSER
    sw      t0, (L + 8)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 8)
    addi    a2, sp, L
    mv      a3, s3
    addi    a4, sp, (L + 16)
    call    lantern_get_domain
    bnez    a0, 7f
    ADDRESS a0, lantern_type_BeaconBlock
    mv      a1, s5
    addi    a2, sp, (L + 16)
    mv      a3, s3
    addi    a4, sp, (L + 72)
    call    lantern_compute_signing_root
    bnez    a0, 7f
    addi    a0, s6, Validator_pubkey
    addi    a1, s2, SignedBeaconBlock_signature
    addi    a2, sp, (L + 48)
    mv      a3, s3
    call    verify_root_signature
    bnez    a0, 7f
    sd      a1, 0(s4)
7:  LEAVE 112
6:  li      a0, LANTERN_INVALID_VALIDATOR_INDEX
    LEAVE 112
SPEC_END verify_block_signature

/*
 * s1 state, s2 signed block, s3 options, s4 config, s5 scratch, s6 result, s7 block,
 * s8 scratch size. Locals: L valid, L+8 state root (32).
 */
SPEC_FUNCTION state_transition
    ENTER 48
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    sd      zero, 0(s6)
    PART    s7, t0, s2, SignedBeaconBlock_message
    ld      s8, 0(s5)
    PART    a1, t0, s7, BeaconBlock_body    # before any change: room and scratch for the slots and the block
    mv      a0, s1
    call    block_room
    bnez    a0, 7f
    mv      a0, s1                          # the epochs the slots cross
    ld      a1, BeaconBlock_slot(s7)
    mv      a2, s5
    li      a3, 0
    call    slots_room
    bnez    a0, 7f
    li      t0, MAX_PENDING_DEPOSITS_PER_EPOCH  # the block's scratch, with every validator they may add
    mul     t0, a1, t0
    LDQ     a2, s1, BeaconState_validators + 8
    add     a2, a2, t0
    PART    a1, t0, s7, BeaconBlock_body
    call    block_scratch
    ld      t0, 0(s5)
    bltu    t0, a0, 9f
    ld      t0, 16(s3)                      # slots_done and a state at the block's slot: no process_slots
    beqz    t0, 3f
    LDQ     t0, s1, BeaconState_slot
    ld      t1, BeaconBlock_slot(s7)
    beq     t0, t1, 4f
3:  mv      a0, s1                          # process_slots(state, block.slot)
    addi    a1, s7, BeaconBlock_slot
    mv      a2, s4
    mv      a3, s5
    mv      a4, s6
    call    lantern_process_slots
    bnez    a0, 7f
    ld      t0, 0(s6)
    bnez    t0, 8f
4:  ld      t0, 0(s3)                       # if validate_result: assert verify_block_signature(state, signed_block)
    beqz    t0, 1f
    sd      s8, 0(s5)
    mv      a0, s1
    mv      a1, s2
    mv      a2, s5
    addi    a3, sp, L
    call    lantern_verify_block_signature
    CHECK_STATUS s6, 7f, 8f
    ld      t0, L(sp)
    bnez    t0, 1f
    li      t0, LANTERN_INVALID_BLOCK_SIGNATURE
    sd      t0, 0(s6)
    j       8f
1:  sd      s8, 0(s5)
    mv      a0, s1                          # process_block(state, block)
    mv      a1, s7
    addi    a2, s3, 8
    mv      a3, s4
    mv      a4, s5
    mv      a5, s6
    call    lantern_process_block
    bnez    a0, 7f
    ld      t0, 0(s6)
    bnez    t0, 8f
    ld      t0, 0(s3)                       # if validate_result: assert block.state_root == hash_tree_root(state)
    beqz    t0, 8f
    sd      s8, 0(s5)
    mv      a0, s1
    ld      a1, CONFIG_STATE_CACHE(s4)
    mv      a2, s5
    addi    a3, sp, (L + 8)
    call    lantern_state_root
    bnez    a0, 7f
    addi    t0, s7, BeaconBlock_state_root
    addi    t1, sp, (L + 8)
    NE32    t0, t1, 2f
    j       8f
2:  li      t0, LANTERN_INVALID_STATE_ROOT
    sd      t0, 0(s6)
8:  li      a0, LANTERN_OK
7:  LEAVE 48
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END state_transition
