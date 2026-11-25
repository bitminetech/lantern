/*
 * Exits, credential changes and execution layer requests, RISC-V.
 * Requirements: docs/reference/block-processing.md.
 * Request public keys and addresses can be 4-aligned only: they are compared a word at a time.
 */

.if FORK >= FORK_ELECTRA
/* Append the PendingDeposit at a1 to state a0; a0 = LANTERN_BUFFER_TOO_SMALL when it has no room. A non-leaf. */
LOCAL_FUNCTION lantern_append_pending_deposit
    FRAME 16
    mv      t0, a0
    LDQ     t1, t0, BeaconState_pending_deposits
    LDQ     t2, t0, BeaconState_pending_deposits + 8
    LDQ     t3, t0, BeaconState_pending_partial_withdrawals
    sub     t3, t3, t1
    addi    t4, t2, 1
    li      t5, PendingDeposit__mem
    mul     t6, t4, t5
    bgtu    t6, t3, 9f
    STQ     t4, t0, BeaconState_pending_deposits + 8
    mul     a0, t2, t5
    add     a0, a0, t1
    add     a0, t0, a0
    li      a2, PendingDeposit__mem
    call    lantern_copy
    li      a0, LANTERN_OK
    UNFRAME 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    UNFRAME 16
END_FUNCTION lantern_append_pending_deposit
.endif

/* ---------------------------------------------------------------- Voluntary exits and credential changes */

/*
 * s1 state, s2 signed exit, s3 config, s4 scratch, s5 result, s6 validator.
 * Locals: L epoch, L+8 predicate, L+16 domain type, L+24 domain (32), L+56 signing root as a ByteList (24 + 32), L+112 pending.
 */
SPEC_FUNCTION process_voluntary_exit
    ENTER 128
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    NEED_SCRATCH s4, s1, 1, 9f
    ld      t0, (SignedVoluntaryExit_message + VoluntaryExit_validator_index)(s2)
    PART    s6, t1, s1, BeaconState_validators
    li      a0, LANTERN_INVALID_VALIDATOR_INDEX # state.validators[voluntary_exit.validator_index]
    bgeu    t0, t1, 6f
    slli    t0, t0, 7
    add     s6, s6, t0
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    mv      a0, s6                          # assert is_active_validator(validator, current epoch)
    addi    a1, sp, L
    addi    a2, sp, (L + 8)
    call    lantern_is_active_validator
    ld      t0, (L + 8)(sp)
    li      a0, LANTERN_INVALID_VOLUNTARY_EXIT
    beqz    t0, 6f
    ld      t0, Validator_exit_epoch(s6)    # assert validator.exit_epoch == FAR_FUTURE_EPOCH
    li      t1, -1
    bne     t0, t1, 6f
    ld      t0, L(sp)                       # assert current epoch >= voluntary_exit.epoch
    ld      t1, (SignedVoluntaryExit_message + VoluntaryExit_epoch)(s2)
    bltu    t0, t1, 6f
    ld      t1, Validator_activation_epoch(s6)  # assert current epoch >= activation_epoch + SHARD_COMMITTEE_PERIOD
    ld      t2, CONFIG_SHARD_COMMITTEE_PERIOD(s3)
    add     t2, t1, t2
    bltu    t2, t1, 5f
    bltu    t0, t2, 6f
.if FORK >= FORK_ELECTRA
    mv      a0, s1                          # assert get_pending_balance_to_withdraw(state, index) == 0
    addi    a1, s2, (SignedVoluntaryExit_message + VoluntaryExit_validator_index)
    addi    a2, sp, (L + 112)
    call    lantern_get_pending_balance_to_withdraw
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (L + 112)(sp)
    li      a0, LANTERN_INVALID_VOLUNTARY_EXIT
    bnez    t0, 6f
.endif
    li      t0, DOMAIN_VOLUNTARY_EXIT
    sw      t0, (L + 16)(sp)
.if FORK >= FORK_DENEB
    addi    a0, sp, (L + 16)                # domain = compute_domain(DOMAIN_VOLUNTARY_EXIT, CAPELLA_FORK_VERSION, gvr)
    addi    a1, s3, CONFIG_CAPELLA_FORK_VERSION
    ADDQ    a2, s1, BeaconState_genesis_validators_root
    mv      a3, s4
    addi    a4, sp, (L + 24)
    call    lantern_compute_domain
.else
    mv      a0, s1                          # domain = get_domain(state, DOMAIN_VOLUNTARY_EXIT, voluntary_exit.epoch)
    addi    a1, sp, (L + 16)
    addi    a2, s2, (SignedVoluntaryExit_message + VoluntaryExit_epoch)
    mv      a3, s4
    addi    a4, sp, (L + 24)
    call    lantern_get_domain
.endif
    bnez    a0, 7f
    ADDRESS a0, lantern_type_VoluntaryExit
    addi    a1, s2, SignedVoluntaryExit_message
    addi    a2, sp, (L + 24)
    mv      a3, s4
    addi    a4, sp, (L + 80)
    call    lantern_compute_signing_root
    bnez    a0, 7f
    addi    a0, s6, Validator_pubkey        # bls.Verify(validator.pubkey, signing_root, signature)
    addi    a1, s2, SignedVoluntaryExit_signature
    addi    a2, sp, (L + 56)
    mv      a3, s4
    call    lantern_verify_root_signature
    bnez    a0, 7f
    li      a0, LANTERN_INVALID_VOLUNTARY_EXIT
    beqz    a1, 6f
    mv      a0, s1                          # initiate_validator_exit(state, voluntary_exit.validator_index)
    addi    a1, s2, (SignedVoluntaryExit_message + VoluntaryExit_validator_index)
    mv      a2, s3
    mv      a3, s4
    mv      a4, s5
    call    lantern_initiate_validator_exit
    j       7f
8:  li      a0, LANTERN_OK
7:  LEAVE 128
5:  li      a0, LANTERN_INVALID_OVERFLOW
6:  sd      a0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 128
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 128
SPEC_END process_voluntary_exit

/*
 * L0: verify a BLS signature over a signing root. a0 public key, a1 signature,
 * a2 an 8-aligned 56-byte buffer whose last 32 bytes hold the root (its first 24 become a
 * ByteList header), a3 scratch. Returns a0 status, a1 valid. Locals: sp+0 valid.
 */
LOCAL_FUNCTION lantern_verify_root_signature
    FRAME 16
    li      t0, 56
    sd      t0, 0(a2)
    li      t0, 24
    sd      t0, 8(a2)
    li      t0, 32
    sd      t0, 16(a2)
    mv      t0, a1
    mv      a1, a2
    mv      a2, t0
    mv      a4, sp
    CALL_GLOBAL crypto_bls_verify           # bls.Verify(public_key, signing_root, signature)
    ld      a1, 0(sp)
    UNFRAME 16
END_FUNCTION lantern_verify_root_signature

.if FORK >= FORK_CAPELLA
/*
 * s1 state, s2 signed change, s3 config, s4 scratch, s5 result, s6 validator.
 * Locals: L digest (32), L+56 ByteList header (24), L+80 signing root (32),
 * L+112 domain type, L+128 domain (32).
 */
SPEC_FUNCTION process_bls_to_execution_change
    ENTER 176
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    NEED_SCRATCH s4, s1, 0, 9f
    ld      t0, (SignedBLSToExecutionChange_message + BLSToExecutionChange_validator_index)(s2)
    PART    s6, t1, s1, BeaconState_validators
    li      a0, LANTERN_INVALID_BLS_CHANGE  # assert address_change.validator_index < len(state.validators)
    bgeu    t0, t1, 6f
    slli    t0, t0, 7
    add     s6, s6, t0
    lbu     t0, Validator_withdrawal_credentials(s6)   # assert prefix == BLS_WITHDRAWAL_PREFIX
    li      t1, BLS_WITHDRAWAL_PREFIX
    bne     t0, t1, 6f
    addi    a0, s2, (SignedBLSToExecutionChange_message + BLSToExecutionChange_from_bls_pubkey)
    li      a1, 48
    addi    a2, sp, L
    call    lantern_sha256_short                    # assert withdrawal_credentials[1:] == sha256(from_bls_pubkey)[1:]
    li      t0, BLS_WITHDRAWAL_PREFIX       # the digest with its first byte set to the prefix just checked
    sb      t0, L(sp)
    addi    t0, s6, Validator_withdrawal_credentials
    addi    t1, sp, L
    li      a0, LANTERN_INVALID_BLS_CHANGE
    NE32    t0, t1, 6f
    li      t0, DOMAIN_BLS_TO_EXECUTION_CHANGE  # compute_domain(DOMAIN_BLS_TO_EXECUTION_CHANGE, GENESIS_FORK_VERSION, gvr)
    sw      t0, (L + 112)(sp)
    addi    a0, sp, (L + 112)
    addi    a1, s3, CONFIG_GENESIS_FORK_VERSION
    ADDQ    a2, s1, BeaconState_genesis_validators_root
    mv      a3, s4
    addi    a4, sp, (L + 128)
    call    lantern_compute_domain
    bnez    a0, 7f
    ADDRESS a0, lantern_type_BLSToExecutionChange
    addi    a1, s2, SignedBLSToExecutionChange_message
    addi    a2, sp, (L + 128)
    mv      a3, s4
    addi    a4, sp, (L + 80)
    call    lantern_compute_signing_root
    bnez    a0, 7f
    addi    a0, s2, (SignedBLSToExecutionChange_message + BLSToExecutionChange_from_bls_pubkey)
    addi    a1, s2, SignedBLSToExecutionChange_signature
    addi    a2, sp, (L + 56)
    mv      a3, s4
    call    lantern_verify_root_signature
    bnez    a0, 7f
    li      a0, LANTERN_INVALID_BLS_CHANGE
    beqz    a1, 6f
    addi    t0, s6, Validator_withdrawal_credentials   # 0x01, 11 zero bytes, to_execution_address
    li      t1, ETH1_ADDRESS_WITHDRAWAL_PREFIX
    sd      t1, 0(t0)
    sw      zero, 8(t0)
    addi    t1, s2, (SignedBLSToExecutionChange_message + BLSToExecutionChange_to_execution_address)
    .irp k, 0, 4, 8, 12, 16
    lw      t2, \k(t1)
    sw      t2, (12 + \k)(t0)
    .endr
    sd      zero, 0(s5)
    li      a0, LANTERN_OK
7:  LEAVE 176
6:  sd      a0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 176
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 176
SPEC_END process_bls_to_execution_change
.endif

/* ---------------------------------------------------------------- Execution layer requests */

.if FORK >= FORK_ELECTRA
/* s1 state, s2 request, s3 result. Locals: L the PendingDeposit. */
SPEC_FUNCTION process_deposit_request
    ENTER 192
    mv      s1, a0
    mv      s2, a1
    mv      s3, a4
    addi    a0, sp, L                       # PendingDeposit(pubkey, withdrawal_credentials, amount, signature, slot=state.slot)
    mv      a1, s2
    li      a2, (DepositRequest_signature + 96)
    call    lantern_copy
    LDQ     t0, s1, BeaconState_slot
    sd      t0, (L + PendingDeposit_slot)(sp)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_append_pending_deposit
    bnez    a0, 7f
.if FORK == FORK_ELECTRA
    LDQ     t0, s1, BeaconState_deposit_requests_start_index
    li      t1, -1                          # == UNSET_DEPOSIT_REQUESTS_START_INDEX: set it
    bne     t0, t1, 1f
    LDQ     t0, s2, DepositRequest_index
    STQ     t0, s1, BeaconState_deposit_requests_start_index
1:
.endif
    sd      zero, 0(s3)
7:  LEAVE 192
SPEC_END process_deposit_request
.endif

.if FORK >= FORK_ELECTRA
.if (DepositRequest_pubkey != PendingDeposit_pubkey) || (DepositRequest_withdrawal_credentials != PendingDeposit_withdrawal_credentials) || (DepositRequest_amount != PendingDeposit_amount) || (DepositRequest_signature != PendingDeposit_signature) || (PendingDeposit_slot != DepositRequest_signature + 96) || (PendingDeposit__mem > 192)
.error "process_deposit_request copies a DepositRequest's first fields into a PendingDeposit"
.endif
.endif

/* Branch to label when the 20 bytes at addr differ from credentials[12:] of validator. Uses a6, a7. */
.macro DIFF_ADDRESS addr, validator, label
    lw      a6, 0(\addr)
    lw      a7, (Validator_withdrawal_credentials + 12)(\validator)
    bne     a6, a7, \label
    lw      a6, 4(\addr)
    lw      a7, (Validator_withdrawal_credentials + 16)(\validator)
    bne     a6, a7, \label
    lw      a6, 8(\addr)
    lw      a7, (Validator_withdrawal_credentials + 20)(\validator)
    bne     a6, a7, \label
    lw      a6, 12(\addr)
    lw      a7, (Validator_withdrawal_credentials + 24)(\validator)
    bne     a6, a7, \label
    lw      a6, 16(\addr)
    lw      a7, (Validator_withdrawal_credentials + 28)(\validator)
    bne     a6, a7, \label
.endm

.if FORK >= FORK_ELECTRA
/*
 * s1 state, s2 request, s3 config, s4 scratch, s5 result, s6 validator, s7 index,
 * s8 amount, s9 pending balance. Locals: L epoch, L+8 predicate, L+16 index, L+24 pending,
 * L+32 to_withdraw, L+40 exit queue epoch.
 */
SPEC_FUNCTION process_withdrawal_request
    ENTER 80
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    NEED_SCRATCH s4, s1, 1, 9f
    LDQ     t0, s1, BeaconState_pending_partial_withdrawals   # room for one pending partial withdrawal
    LDQ     t1, s1, BeaconState_pending_partial_withdrawals + 8
    LDQ     t2, s1, BeaconState_pending_consolidations
    sub     t2, t2, t0
    addi    t1, t1, 1
    li      t3, PendingPartialWithdrawal__mem
    mul     t1, t1, t3
    bgtu    t1, t2, 9f
    sd      zero, 0(s5)
    ld      s8, WithdrawalRequest_amount(s2)
    LDQ     t0, s1, BeaconState_pending_partial_withdrawals + 8
    li      t1, PENDING_PARTIAL_WITHDRAWALS_LIMIT
    bne     t0, t1, 1f                      # queue full, and not a full exit
    li      t1, FULL_EXIT_REQUEST_AMOUNT
    bne     s8, t1, 8f
1:  mv      a0, s1
    addi    a1, s2, WithdrawalRequest_validator_pubkey
    call    lantern_find_pubkey
    li      t0, -1
    beq     a0, t0, 8f
    mv      s7, a0
    sd      s7, (L + 16)(sp)
    PART    s6, t0, s1, BeaconState_validators
    slli    t0, s7, 7
    add     s6, s6, t0
    mv      a0, s6
    addi    a1, sp, (L + 8)
    call    lantern_has_execution_withdrawal_credential
    ld      t0, (L + 8)(sp)
    beqz    t0, 8f
    addi    t0, s2, WithdrawalRequest_source_address
    DIFF_ADDRESS t0, s6, 8f
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    mv      a0, s6
    addi    a1, sp, L
    addi    a2, sp, (L + 8)
    call    lantern_is_active_validator
    ld      t0, (L + 8)(sp)
    beqz    t0, 8f
    ld      t0, Validator_exit_epoch(s6)
    li      t1, -1
    bne     t0, t1, 8f
    ld      t0, Validator_activation_epoch(s6)
    ld      t1, CONFIG_SHARD_COMMITTEE_PERIOD(s3)
    add     t1, t0, t1
    bltu    t1, t0, 5f
    ld      t0, L(sp)
    bltu    t0, t1, 8f
    mv      a0, s1
    addi    a1, sp, (L + 16)
    addi    a2, sp, (L + 24)
    call    lantern_get_pending_balance_to_withdraw
    CHECK_STATUS s5, 7f, 8f
    ld      s9, (L + 24)(sp)
    bnez    s8, 2f
    bnez    s9, 8f                          # a full exit, when nothing is pending
    mv      a0, s1
    addi    a1, sp, (L + 16)
    mv      a2, s3
    mv      a3, s4
    mv      a4, s5
    call    lantern_initiate_validator_exit
    j       7f
2:  mv      a0, s6
    addi    a1, sp, (L + 8)
    call    lantern_has_compounding_withdrawal_credential
    ld      t0, (L + 8)(sp)
    beqz    t0, 8f
    ld      t0, Validator_effective_balance(s6)
    li      t1, MIN_ACTIVATION_BALANCE
    bltu    t0, t1, 8f                      # has_sufficient_effective_balance
    PART    t2, t3, s1, BeaconState_balances
    slli    t3, s7, 3
    add     t2, t2, t3
    ld      t2, 0(t2)
    add     t3, t1, s9                      # has_excess_balance: balance > MIN_ACTIVATION_BALANCE + pending
    bltu    t3, t1, 5f
    bleu    t2, t3, 8f
    sub     t2, t2, t3                      # to_withdraw = min(balance - MIN_ACTIVATION_BALANCE - pending, amount)
    bltu    t2, s8, 3f
    mv      t2, s8
3:  sd      t2, (L + 32)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 32)
    mv      a2, s3
    mv      a3, s4
    addi    a4, sp, (L + 40)
    mv      a5, s5
    call    lantern_compute_exit_epoch_and_update_churn
    bnez    a0, 7f
    ld      t0, 0(s5)
    bnez    t0, 8f
    ld      t0, (L + 40)(sp)                # withdrawable_epoch = exit_queue_epoch + MIN_VALIDATOR_WITHDRAWABILITY_DELAY
    ld      t1, CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY(s3)
    add     t1, t0, t1
    bltu    t1, t0, 5f
    PART    t2, t3, s1, BeaconState_pending_partial_withdrawals
    li      t4, PendingPartialWithdrawal__mem
    mul     t4, t3, t4
    add     t2, t2, t4
    sd      s7, PendingPartialWithdrawal_validator_index(t2)
    ld      t4, (L + 32)(sp)
    sd      t4, PendingPartialWithdrawal_amount(t2)
    sd      t1, PendingPartialWithdrawal_withdrawable_epoch(t2)
    addi    t3, t3, 1
    STQ     t3, s1, BeaconState_pending_partial_withdrawals + 8
8:  li      a0, LANTERN_OK
7:  LEAVE 80
5:  li      t0, LANTERN_INVALID_OVERFLOW
    sd      t0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 80
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
SPEC_END process_withdrawal_request
.endif

.if FORK >= FORK_ELECTRA
/* s1 state, s2 request, s3 out, s4 validator. Locals: L epoch, L+8 predicate. */
SPEC_FUNCTION is_valid_switch_to_compounding_request
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    sd      zero, 0(s3)
    addi    t0, s2, ConsolidationRequest_source_pubkey  # source_pubkey == target_pubkey
    addi    t1, s2, ConsolidationRequest_target_pubkey
    NE48W   t0, t1, 8f
    mv      a0, s1
    mv      a1, t0
    call    lantern_find_pubkey
    li      t0, -1
    beq     a0, t0, 8f
    PART    s4, t0, s1, BeaconState_validators
    slli    t0, a0, 7
    add     s4, s4, t0
    addi    t0, s2, ConsolidationRequest_source_address
    DIFF_ADDRESS t0, s4, 8f
    mv      a0, s4
    addi    a1, sp, (L + 8)
    call    lantern_has_eth1_withdrawal_credential
    ld      t0, (L + 8)(sp)
    beqz    t0, 8f
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    mv      a0, s4
    addi    a1, sp, L
    addi    a2, sp, (L + 8)
    call    lantern_is_active_validator
    ld      t0, (L + 8)(sp)
    beqz    t0, 8f
    ld      t0, Validator_exit_epoch(s4)
    li      t1, -1
    bne     t0, t1, 8f
    li      t0, 1
    sd      t0, 0(s3)
8:  li      a0, LANTERN_OK
    LEAVE 16
SPEC_END is_valid_switch_to_compounding_request
.endif

.if FORK >= FORK_ELECTRA
/* s1 state, s2 index. Locals: L the PendingDeposit (PendingDeposit__mem). */
SPEC_FUNCTION queue_excess_active_balance
    ENTER 192
    mv      s1, a0
    ld      s2, 0(a1)
    PART    t0, t1, s1, BeaconState_balances
    slli    t1, s2, 3
    add     t0, t0, t1                      # &balances[index]
    ld      t2, 0(t0)
    li      t3, MIN_ACTIVATION_BALANCE
    bleu    t2, t3, 8f
    LDQ     t4, s1, BeaconState_pending_deposits        # room first: the state must not change on failure
    LDQ     t5, s1, BeaconState_pending_deposits + 8
    LDQ     t6, s1, BeaconState_pending_partial_withdrawals
    sub     t6, t6, t4
    addi    t5, t5, 1
    li      t4, PendingDeposit__mem
    mul     t5, t5, t4
    bgtu    t5, t6, 9f
    sub     t4, t2, t3                      # excess_balance
    sd      t4, (L + PendingDeposit_amount)(sp)
    sd      t3, 0(t0)                       # balances[index] = MIN_ACTIVATION_BALANCE
    PART    t0, t1, s1, BeaconState_validators
    slli    t1, s2, 7
    add     t0, t0, t1
    addi    a0, sp, (L + PendingDeposit_pubkey)
    addi    a1, t0, Validator_pubkey
    li      a2, (48 + 32)                   # pubkey and withdrawal_credentials
    call    lantern_copy
    addi    a0, sp, (L + PendingDeposit_signature)      # G2_POINT_AT_INFINITY
    li      a1, 96
    call    lantern_zero
    li      t0, 0xc0
    sb      t0, (L + PendingDeposit_signature)(sp)
    li      t0, GENESIS_SLOT
    sd      t0, (L + PendingDeposit_slot)(sp)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_append_pending_deposit
    LEAVE 192
8:  li      a0, LANTERN_OK
    LEAVE 192
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 192
SPEC_END queue_excess_active_balance
.endif

.if FORK >= FORK_ELECTRA
.if (Validator_withdrawal_credentials != Validator_pubkey + 48) || (PendingDeposit_withdrawal_credentials != PendingDeposit_pubkey + 48)
.error "lantern_queue_excess_active_balance copies pubkey and credentials together"
.endif
.endif

.if FORK >= FORK_ELECTRA
/* s1 state, s2 index pointer. */
SPEC_FUNCTION switch_to_compounding_validator
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    LDQ     t4, s1, BeaconState_pending_deposits        # room for the excess deposit, before any change
    LDQ     t5, s1, BeaconState_pending_deposits + 8
    LDQ     t6, s1, BeaconState_pending_partial_withdrawals
    sub     t6, t6, t4
    addi    t5, t5, 1
    li      t4, PendingDeposit__mem
    mul     t5, t5, t4
    bgtu    t5, t6, 9f
    ld      t0, 0(s2)
    PART    t1, t2, s1, BeaconState_validators
    slli    t0, t0, 7
    add     t1, t1, t0
    li      t2, COMPOUNDING_WITHDRAWAL_PREFIX
    sb      t2, Validator_withdrawal_credentials(t1)
    mv      a0, s1
    mv      a1, s2
    call    lantern_queue_excess_active_balance
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END switch_to_compounding_validator
.endif

.if FORK >= FORK_ELECTRA
/*
 * s1 state, s2 balance, s3 config, s4 scratch, s5 out, s6 earliest, s7 churn,
 * s8 to consume, s9 result. Locals: L current epoch, L+8 activation exit epoch, L+16 churn.
 */
SPEC_FUNCTION compute_consolidation_epoch_and_update_churn
    ENTER 32
    mv      s1, a0
    ld      s2, 0(a1)
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s9, a5
    NEED_SCRATCH s4, s1, 1, 9f
    sd      zero, 0(s9)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    addi    a0, sp, L
    addi    a1, sp, (L + 8)
    call    lantern_compute_activation_exit_epoch
    LDQ     t0, s1, BeaconState_earliest_consolidation_epoch
    ld      t1, (L + 8)(sp)
    mv      s6, t0
    bgtu    t0, t1, 1f
    mv      s6, t1
1:  mv      a0, s1
    mv      a1, s3
    mv      a2, s4
    addi    a3, sp, (L + 16)
    call    lantern_get_consolidation_churn_limit
    bnez    a0, 7f
    ld      s7, (L + 16)(sp)
    LDQ     t0, s1, BeaconState_earliest_consolidation_epoch
    LDQ     s8, s1, BeaconState_consolidation_balance_to_consume
    bgeu    t0, s6, 2f
    mv      s8, s7
2:  bleu    s2, s8, 3f
    beqz    s7, 6f                          # the spec divides by the churn
    sub     t0, s2, s8
    addi    t0, t0, -1
    divu    t0, t0, s7
    addi    t0, t0, 1
    add     t1, s6, t0
    bltu    t1, s6, 6f
    mv      s6, t1
    mul     t1, t0, s7
    mulhu   t2, t0, s7
    bnez    t2, 6f
    add     t2, s8, t1
    bltu    t2, s8, 6f
    mv      s8, t2
3:  sub     s8, s8, s2
    STQ     s8, s1, BeaconState_consolidation_balance_to_consume
    STQ     s6, s1, BeaconState_earliest_consolidation_epoch
    sd      s6, 0(s5)
    li      a0, LANTERN_OK
7:  LEAVE 32
6:  li      t0, LANTERN_INVALID_OVERFLOW
    sd      t0, 0(s9)
    li      a0, LANTERN_OK
    LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END compute_consolidation_epoch_and_update_churn
.endif

.if FORK >= FORK_ELECTRA
/*
 * s1 state, s2 request, s3 config, s4 scratch, s5 result, s6 source, s7 target,
 * s8 source index, s9 target index. Locals: L predicate, L+8 epoch, L+16 churn, L+24 pending,
 * L+32 index, L+40 exit epoch.
 */
SPEC_FUNCTION process_consolidation_request
    ENTER 48
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    NEED_SCRATCH s4, s1, 1, 9f
    LDQ     t0, s1, BeaconState_pending_deposits        # room: one pending deposit or one pending consolidation
    LDQ     t1, s1, BeaconState_pending_deposits + 8
    LDQ     t2, s1, BeaconState_pending_partial_withdrawals
    sub     t2, t2, t0
    addi    t1, t1, 1
    li      t3, PendingDeposit__mem
    mul     t1, t1, t3
    bgtu    t1, t2, 9f
    LDQ     t0, s1, BeaconState_pending_consolidations
    LDQ     t1, s1, BeaconState_pending_consolidations + 8
    ld      t2, 0(s1)
    sub     t2, t2, t0
    addi    t1, t1, 1
    slli    t1, t1, 4
    bgtu    t1, t2, 9f
    sd      zero, 0(s5)
    mv      a0, s1
    mv      a1, s2
    addi    a2, sp, L
    call    lantern_is_valid_switch_to_compounding_request
    ld      t0, L(sp)
    beqz    t0, 1f
    mv      a0, s1                          # switch_to_compounding_validator(state, source_index)
    addi    a1, s2, ConsolidationRequest_source_pubkey
    call    lantern_find_pubkey
    sd      a0, (L + 32)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 32)
    call    lantern_switch_to_compounding_validator
    j       7f
1:  addi    t0, s2, ConsolidationRequest_source_pubkey  # source_pubkey == target_pubkey: return
    addi    t1, s2, ConsolidationRequest_target_pubkey
    NE48W   t0, t1, 2f
    j       8f
2:  LDQ     t0, s1, BeaconState_pending_consolidations + 8
    li      t1, PENDING_CONSOLIDATIONS_LIMIT
    beq     t0, t1, 8f
    mv      a0, s1                          # get_consolidation_churn_limit(state) <= MIN_ACTIVATION_BALANCE: return
    mv      a1, s3
    mv      a2, s4
    addi    a3, sp, (L + 16)
    call    lantern_get_consolidation_churn_limit
    bnez    a0, 7f
    ld      t0, (L + 16)(sp)
    li      t1, MIN_ACTIVATION_BALANCE
    bleu    t0, t1, 8f
    mv      a0, s1
    addi    a1, s2, ConsolidationRequest_source_pubkey
    call    lantern_find_pubkey
    li      t0, -1
    beq     a0, t0, 8f
    mv      s8, a0
    mv      a0, s1
    addi    a1, s2, ConsolidationRequest_target_pubkey
    call    lantern_find_pubkey
    li      t0, -1
    beq     a0, t0, 8f
    mv      s9, a0
    PART    s6, t0, s1, BeaconState_validators
    slli    t0, s9, 7
    add     s7, s6, t0
    slli    t0, s8, 7
    add     s6, s6, t0
    mv      a0, s6
    addi    a1, sp, L
    call    lantern_has_execution_withdrawal_credential
    ld      t0, L(sp)
    beqz    t0, 8f
    addi    t0, s2, ConsolidationRequest_source_address
    DIFF_ADDRESS t0, s6, 8f
    mv      a0, s7
    addi    a1, sp, L
    call    lantern_has_compounding_withdrawal_credential
    ld      t0, L(sp)
    beqz    t0, 8f
    mv      a0, s1
    addi    a1, sp, (L + 8)
    call    lantern_get_current_epoch
    mv      a0, s6
    addi    a1, sp, (L + 8)
    addi    a2, sp, L
    call    lantern_is_active_validator
    ld      t0, L(sp)
    beqz    t0, 8f
    mv      a0, s7
    addi    a1, sp, (L + 8)
    addi    a2, sp, L
    call    lantern_is_active_validator
    ld      t0, L(sp)
    beqz    t0, 8f
    li      t1, -1
    ld      t0, Validator_exit_epoch(s6)
    bne     t0, t1, 8f
    ld      t0, Validator_exit_epoch(s7)
    bne     t0, t1, 8f
    ld      t0, Validator_activation_epoch(s6)
    ld      t1, CONFIG_SHARD_COMMITTEE_PERIOD(s3)
    add     t1, t0, t1
    bltu    t1, t0, 5f
    ld      t0, (L + 8)(sp)
    bltu    t0, t1, 8f
    sd      s8, (L + 32)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 32)
    addi    a2, sp, (L + 24)
    call    lantern_get_pending_balance_to_withdraw
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (L + 24)(sp)
    bnez    t0, 8f
    mv      a0, s1                          # source.exit_epoch = compute_consolidation_epoch_and_update_churn(...)
    addi    a1, s6, Validator_effective_balance
    mv      a2, s3
    mv      a3, s4
    addi    a4, sp, (L + 40)
    mv      a5, s5
    call    lantern_compute_consolidation_epoch_and_update_churn
    bnez    a0, 7f
    ld      t0, 0(s5)
    bnez    t0, 8f
    ld      t0, (L + 40)(sp)
    sd      t0, Validator_exit_epoch(s6)
    ld      t1, CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY(s3)
    add     t1, t0, t1
    bltu    t1, t0, 5f
    sd      t1, Validator_withdrawable_epoch(s6)
    PART    t0, t1, s1, BeaconState_pending_consolidations
    slli    t2, t1, 4
    add     t0, t0, t2
    sd      s8, PendingConsolidation_source_index(t0)
    sd      s9, PendingConsolidation_target_index(t0)
    addi    t1, t1, 1
    STQ     t1, s1, BeaconState_pending_consolidations + 8
8:  li      a0, LANTERN_OK
7:  LEAVE 48
5:  li      t0, LANTERN_INVALID_OVERFLOW
    sd      t0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 48
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END process_consolidation_request
.endif
