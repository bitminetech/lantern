/*
 * Exits, credential changes and execution layer requests, ARM64.
 * Requirements: docs/reference/block-processing.md.
 */

/* Append the PendingDeposit at x1 to state x0; x0 = LANTERN_BUFFER_TOO_SMALL when it has no room. A non-leaf. */
LOCAL_FUNCTION append_pending_deposit
    FRAME 16
    mov     x9, x0
    LDQ     x10, x9, BeaconState_pending_deposits
    LDQ     x11, x9, BeaconState_pending_deposits + 8
    LDQ     x12, x9, BeaconState_pending_partial_withdrawals
    sub     x12, x12, x10
    add     x13, x11, #1
    mov     x14, #PendingDeposit__mem
    mul     x15, x13, x14
    cmp     x15, x12
    b.hi    9f
    STQ     x13, x9, BeaconState_pending_deposits + 8
    madd    x0, x11, x14, x10
    add     x0, x9, x0
    mov     x2, #PendingDeposit__mem
    bl      lantern_copy
    mov     x0, #LANTERN_OK
    UNFRAME 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    UNFRAME 16
END_FUNCTION append_pending_deposit

/* ---------------------------------------------------------------- Voluntary exits and credential changes */

/*
 * x19 state, x20 signed exit, x21 config, x22 scratch, x23 result, x24 validator.
 * Locals: L epoch, L+8 predicate, L+16 domain type, L+24 domain (32), L+56 signing root as a ByteList (24 + 32), L+112 pending.
 */
FUNCTION lantern_process_voluntary_exit
    ENTER 128
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    NEED_SCRATCH x22, x19, 1, 9f
    ldr     x9, [x20, #(SignedVoluntaryExit_message + VoluntaryExit_validator_index)]
    PART    x24, x10, x19, BeaconState_validators
    cmp     x9, x10                         /* state.validators[voluntary_exit.validator_index] */
    mov     x0, #LANTERN_INVALID_VALIDATOR_INDEX
    b.hs    6f
    add     x24, x24, x9, lsl #7
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    mov     x0, x24                         /* assert is_active_validator(validator, current epoch) */
    add     x1, sp, #L
    add     x2, sp, #(L + 8)
    bl      lantern_is_active_validator
    ldr     x9, [sp, #(L + 8)]
    mov     x0, #LANTERN_INVALID_VOLUNTARY_EXIT
    cbz     x9, 6f
    ldr     x9, [x24, #Validator_exit_epoch]    /* assert validator.exit_epoch == FAR_FUTURE_EPOCH */
    cmn     x9, #1
    b.ne    6f
    ldr     x9, [sp, #L]                    /* assert current epoch >= voluntary_exit.epoch */
    ldr     x10, [x20, #(SignedVoluntaryExit_message + VoluntaryExit_epoch)]
    cmp     x9, x10
    b.lo    6f
    ldr     x10, [x24, #Validator_activation_epoch]  /* assert current epoch >= activation_epoch + SHARD_COMMITTEE_PERIOD */
    ldr     x11, [x21, #CONFIG_SHARD_COMMITTEE_PERIOD]
    adds    x10, x10, x11
    b.cs    5f
    cmp     x9, x10
    b.lo    6f
    mov     x0, x19                         /* assert get_pending_balance_to_withdraw(state, index) == 0 */
    add     x1, x20, #(SignedVoluntaryExit_message + VoluntaryExit_validator_index)
    add     x2, sp, #(L + 112)
    bl      lantern_get_pending_balance_to_withdraw
    CHECK_STATUS x23, 7f, 8f
    ldr     x9, [sp, #(L + 112)]
    mov     x0, #LANTERN_INVALID_VOLUNTARY_EXIT
    cbnz    x9, 6f
    mov     w9, #DOMAIN_VOLUNTARY_EXIT      /* domain = compute_domain(DOMAIN_VOLUNTARY_EXIT, CAPELLA_FORK_VERSION, gvr) */
    str     w9, [sp, #(L + 16)]
    add     x0, sp, #(L + 16)
    add     x1, x21, #CONFIG_CAPELLA_FORK_VERSION
    ADDQ    x2, x19, BeaconState_genesis_validators_root
    mov     x3, x22
    add     x4, sp, #(L + 24)
    bl      lantern_compute_domain
    cbnz    x0, 7f
    ADDRESS x0, lantern_type_VoluntaryExit
    add     x1, x20, #SignedVoluntaryExit_message
    add     x2, sp, #(L + 24)
    mov     x3, x22
    add     x4, sp, #(L + 80)
    bl      lantern_compute_signing_root
    cbnz    x0, 7f
    add     x0, x24, #Validator_pubkey
    add     x1, x20, #SignedVoluntaryExit_signature
    add     x2, sp, #(L + 56)
    mov     x3, x22
    bl      verify_root_signature           /* bls.Verify(validator.pubkey, signing_root, signature) */
    cbnz    x0, 7f
    mov     x0, #LANTERN_INVALID_VOLUNTARY_EXIT
    cbz     x1, 6f
    mov     x0, x19                         /* initiate_validator_exit(state, voluntary_exit.validator_index) */
    add     x1, x20, #(SignedVoluntaryExit_message + VoluntaryExit_validator_index)
    mov     x2, x21
    mov     x3, x22
    mov     x4, x23
    bl      lantern_initiate_validator_exit
    b       7f
8:  mov     x0, #LANTERN_OK
7:  LEAVE 128
5:  mov     x0, #LANTERN_INVALID_OVERFLOW
6:  str     x0, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 128
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 128
END_FUNCTION lantern_process_voluntary_exit

/*
 * L0: verify a BLS signature over a signing root. x0 public key, x1 signature,
 * x2 a 56-byte buffer whose last 32 bytes hold the root (its first 24 become a
 * ByteList header), x3 scratch. Returns x0 status, x1 valid.
 */
LOCAL_FUNCTION verify_root_signature
    FRAME 16
    mov     x11, #56
    str     x11, [x2]
    mov     x11, #24
    str     x11, [x2, #8]
    mov     x11, #32
    str     x11, [x2, #16]
    mov     x9, x1
    mov     x1, x2
    mov     x2, x9
    add     x4, sp, #16
    CALL_GLOBAL crypto_bls_verify           /* bls.Verify(public_key, signing_root, signature) */
    ldr     x1, [sp, #16]
    UNFRAME 16
END_FUNCTION verify_root_signature

/*
 * x19 state, x20 signed change, x21 config, x22 scratch, x23 result, x24 validator.
 * Locals: L digest (32), L+32 zero root, L+56 ByteList header (24), L+80 signing root (32),
 * L+112 domain type, L+120 domain... domain at L+128 (32).
 */
FUNCTION lantern_process_bls_to_execution_change
    ENTER 176
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    NEED_SCRATCH x22, x19, 0, 9f
    ldr     x9, [x20, #(SignedBLSToExecutionChange_message + BLSToExecutionChange_validator_index)]
    PART    x24, x10, x19, BeaconState_validators
    cmp     x9, x10                         /* assert address_change.validator_index < len(state.validators) */
    mov     x0, #LANTERN_INVALID_BLS_CHANGE
    b.hs    6f
    add     x24, x24, x9, lsl #7
    ldrb    w9, [x24, #Validator_withdrawal_credentials]   /* assert prefix == BLS_WITHDRAWAL_PREFIX */
    cmp     w9, #BLS_WITHDRAWAL_PREFIX
    b.ne    6f
    add     x0, x20, #(SignedBLSToExecutionChange_message + BLSToExecutionChange_from_bls_pubkey)
    mov     x1, #48
    add     x2, sp, #L
    bl      sha256_short                    /* assert withdrawal_credentials[1:] == sha256(from_bls_pubkey)[1:] */
    mov     w9, #BLS_WITHDRAWAL_PREFIX      /* the digest with its first byte set to the prefix just checked */
    strb    w9, [sp, #L]
    add     x14, x24, #Validator_withdrawal_credentials
    add     x15, sp, #L
    mov     x0, #LANTERN_INVALID_BLS_CHANGE
    NE32    x14, x15, 6f
    mov     w9, #DOMAIN_BLS_TO_EXECUTION_CHANGE  /* compute_domain(DOMAIN_BLS_TO_EXECUTION_CHANGE, GENESIS_FORK_VERSION, gvr) */
    str     w9, [sp, #(L + 112)]
    add     x0, sp, #(L + 112)
    add     x1, x21, #CONFIG_GENESIS_FORK_VERSION
    ADDQ    x2, x19, BeaconState_genesis_validators_root
    mov     x3, x22
    add     x4, sp, #(L + 128)
    bl      lantern_compute_domain
    cbnz    x0, 7f
    ADDRESS x0, lantern_type_BLSToExecutionChange
    add     x1, x20, #SignedBLSToExecutionChange_message
    add     x2, sp, #(L + 128)
    mov     x3, x22
    add     x4, sp, #(L + 80)
    bl      lantern_compute_signing_root
    cbnz    x0, 7f
    add     x0, x20, #(SignedBLSToExecutionChange_message + BLSToExecutionChange_from_bls_pubkey)
    add     x1, x20, #SignedBLSToExecutionChange_signature
    add     x2, sp, #(L + 56)
    mov     x3, x22
    bl      verify_root_signature
    cbnz    x0, 7f
    mov     x0, #LANTERN_INVALID_BLS_CHANGE
    cbz     x1, 6f
    add     x9, x24, #Validator_withdrawal_credentials     /* 0x01, 11 zero bytes, to_execution_address */
    mov     w10, #ETH1_ADDRESS_WITHDRAWAL_PREFIX
    str     x10, [x9]
    str     wzr, [x9, #8]
    add     x10, x20, #(SignedBLSToExecutionChange_message + BLSToExecutionChange_to_execution_address)
    ldr     w11, [x10]
    str     w11, [x9, #12]
    ldr     x11, [x10, #4]
    str     x11, [x9, #16]
    ldr     x11, [x10, #12]
    str     x11, [x9, #24]
    str     xzr, [x23]
    mov     x0, #LANTERN_OK
7:  LEAVE 176
6:  str     x0, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 176
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 176
END_FUNCTION lantern_process_bls_to_execution_change

/* ---------------------------------------------------------------- Execution layer requests */

/* x19 state, x20 request, x21 result. Locals: L the PendingDeposit. */
FUNCTION lantern_process_deposit_request
    ENTER 192
    mov     x19, x0
    mov     x20, x1
    mov     x21, x4
    add     x0, sp, #L                      /* PendingDeposit(pubkey, withdrawal_credentials, amount, signature, slot=state.slot) */
    mov     x1, x20
    mov     x2, #(DepositRequest_signature + 96)
    bl      lantern_copy
    LDQ     x9, x19, BeaconState_slot
    str     x9, [sp, #(L + PendingDeposit_slot)]
    mov     x0, x19
    add     x1, sp, #L
    bl      append_pending_deposit
    cbnz    x0, 7f
    str     xzr, [x21]
7:  LEAVE 192
END_FUNCTION lantern_process_deposit_request

.if (DepositRequest_pubkey != PendingDeposit_pubkey) || (DepositRequest_withdrawal_credentials != PendingDeposit_withdrawal_credentials) || (DepositRequest_amount != PendingDeposit_amount) || (DepositRequest_signature != PendingDeposit_signature) || (PendingDeposit_slot != DepositRequest_signature + 96) || (PendingDeposit__mem > 192)
.error "process_deposit_request copies a DepositRequest's first fields into a PendingDeposit"
.endif

/* Whether the 20 bytes at x0 equal credentials[12:] of validator x1: Z set when equal. Uses x9-x12. */
.macro SAME_ADDRESS addr, validator
    ldr     x9, [\addr]
    ldr     x10, [\validator, #(Validator_withdrawal_credentials + 12)]
    ldr     x11, [\addr, #8]
    ldr     x12, [\validator, #(Validator_withdrawal_credentials + 20)]
    cmp     x9, x10
    ccmp    x11, x12, #0, eq
    ldr     w9, [\addr, #16]
    ldr     w10, [\validator, #(Validator_withdrawal_credentials + 28)]
    ccmp    w9, w10, #0, eq
.endm

/*
 * x19 state, x20 request, x21 config, x22 scratch, x23 result, x24 validator, x25 index,
 * x26 amount, x27 pending balance. Locals: L epoch, L+8 predicate, L+16 index, L+24 pending,
 * L+32 to_withdraw, L+40 exit queue epoch, L+48 the PendingPartialWithdrawal (24).
 */
FUNCTION lantern_process_withdrawal_request
    ENTER 80
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    NEED_SCRATCH x22, x19, 1, 9f
    LDQ     x9, x19, BeaconState_pending_partial_withdrawals      /* room for one pending partial withdrawal */
    LDQ     x10, x19, BeaconState_pending_partial_withdrawals + 8
    LDQ     x11, x19, BeaconState_pending_consolidations
    sub     x11, x11, x9
    add     x10, x10, #1
    mov     x12, #PendingPartialWithdrawal__mem
    mul     x10, x10, x12
    cmp     x10, x11
    b.hi    9f
    str     xzr, [x23]
    ldr     x26, [x20, #WithdrawalRequest_amount]
    LDQ     x9, x19, BeaconState_pending_partial_withdrawals + 8
    MOVQ    x10, PENDING_PARTIAL_WITHDRAWALS_LIMIT
    cmp     x9, x10                         /* queue full, and not a full exit */
    ccmp    x26, #FULL_EXIT_REQUEST_AMOUNT, #4, eq
    b.ne    8f
    mov     x0, x19
    add     x1, x20, #WithdrawalRequest_validator_pubkey
    bl      find_pubkey
    cmn     x0, #1
    b.eq    8f
    mov     x25, x0
    str     x25, [sp, #(L + 16)]
    PART    x24, x9, x19, BeaconState_validators
    add     x24, x24, x25, lsl #7
    mov     x0, x24
    add     x1, sp, #(L + 8)
    bl      lantern_has_execution_withdrawal_credential
    ldr     x9, [sp, #(L + 8)]
    cbz     x9, 8f
    add     x14, x20, #WithdrawalRequest_source_address
    SAME_ADDRESS x14, x24
    b.ne    8f
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    mov     x0, x24
    add     x1, sp, #L
    add     x2, sp, #(L + 8)
    bl      lantern_is_active_validator
    ldr     x9, [sp, #(L + 8)]
    cbz     x9, 8f
    ldr     x9, [x24, #Validator_exit_epoch]
    cmn     x9, #1
    b.ne    8f
    ldr     x9, [x24, #Validator_activation_epoch]
    ldr     x10, [x21, #CONFIG_SHARD_COMMITTEE_PERIOD]
    adds    x9, x9, x10
    b.cs    5f
    ldr     x10, [sp, #L]
    cmp     x10, x9
    b.lo    8f
    mov     x0, x19
    add     x1, sp, #(L + 16)
    add     x2, sp, #(L + 24)
    bl      lantern_get_pending_balance_to_withdraw
    CHECK_STATUS x23, 7f, 8f
    ldr     x27, [sp, #(L + 24)]
    cbnz    x26, 1f
    cbnz    x27, 8f                         /* a full exit, when nothing is pending */
    mov     x0, x19
    add     x1, sp, #(L + 16)
    mov     x2, x21
    mov     x3, x22
    mov     x4, x23
    bl      lantern_initiate_validator_exit
    b       7f
1:  mov     x0, x24
    add     x1, sp, #(L + 8)
    bl      lantern_has_compounding_withdrawal_credential
    ldr     x9, [sp, #(L + 8)]
    cbz     x9, 8f
    ldr     x9, [x24, #Validator_effective_balance]
    MOVQ    x10, MIN_ACTIVATION_BALANCE
    cmp     x9, x10                         /* has_sufficient_effective_balance */
    b.lo    8f
    PART    x11, x12, x19, BeaconState_balances
    ldr     x11, [x11, x25, lsl #3]
    adds    x12, x10, x27                   /* has_excess_balance: balance > MIN_ACTIVATION_BALANCE + pending */
    b.cs    5f
    cmp     x11, x12
    b.ls    8f
    sub     x11, x11, x12                   /* to_withdraw = min(balance - MIN_ACTIVATION_BALANCE - pending, amount) */
    cmp     x11, x26
    csel    x11, x11, x26, lo
    str     x11, [sp, #(L + 32)]
    mov     x0, x19
    add     x1, sp, #(L + 32)
    mov     x2, x21
    mov     x3, x22
    add     x4, sp, #(L + 40)
    mov     x5, x23
    bl      lantern_compute_exit_epoch_and_update_churn
    cbnz    x0, 7f
    ldr     x9, [x23]
    cbnz    x9, 8f
    ldr     x9, [sp, #(L + 40)]             /* withdrawable_epoch = exit_queue_epoch + MIN_VALIDATOR_WITHDRAWABILITY_DELAY */
    ldr     x10, [x21, #CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY]
    adds    x9, x9, x10
    b.cs    5f
    PART    x10, x11, x19, BeaconState_pending_partial_withdrawals
    mov     x12, #PendingPartialWithdrawal__mem
    madd    x10, x11, x12, x10
    str     x25, [x10, #PendingPartialWithdrawal_validator_index]
    ldr     x12, [sp, #(L + 32)]
    str     x12, [x10, #PendingPartialWithdrawal_amount]
    str     x9, [x10, #PendingPartialWithdrawal_withdrawable_epoch]
    add     x11, x11, #1
    STQ     x11, x19, BeaconState_pending_partial_withdrawals + 8
8:  mov     x0, #LANTERN_OK
7:  LEAVE 80
5:  mov     x9, #LANTERN_INVALID_OVERFLOW
    str     x9, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 80
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
END_FUNCTION lantern_process_withdrawal_request

/* x19 state, x20 request, x21 out, x22 validator. Locals: L epoch, L+8 predicate. */
FUNCTION lantern_is_valid_switch_to_compounding_request
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    str     xzr, [x21]
    add     x14, x20, #ConsolidationRequest_source_pubkey   /* source_pubkey == target_pubkey */
    add     x15, x20, #ConsolidationRequest_target_pubkey
    ldp     x9, x10, [x14]
    ldp     x11, x12, [x15]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    8f
    ldp     x9, x10, [x14, #16]
    ldp     x11, x12, [x15, #16]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    8f
    ldp     x9, x10, [x14, #32]
    ldp     x11, x12, [x15, #32]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    8f
    mov     x0, x19
    mov     x1, x14
    bl      find_pubkey
    cmn     x0, #1
    b.eq    8f
    PART    x22, x9, x19, BeaconState_validators
    add     x22, x22, x0, lsl #7
    add     x14, x20, #ConsolidationRequest_source_address
    SAME_ADDRESS x14, x22
    b.ne    8f
    mov     x0, x22
    add     x1, sp, #(L + 8)
    bl      lantern_has_eth1_withdrawal_credential
    ldr     x9, [sp, #(L + 8)]
    cbz     x9, 8f
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    mov     x0, x22
    add     x1, sp, #L
    add     x2, sp, #(L + 8)
    bl      lantern_is_active_validator
    ldr     x9, [sp, #(L + 8)]
    cbz     x9, 8f
    ldr     x9, [x22, #Validator_exit_epoch]
    cmn     x9, #1
    b.ne    8f
    mov     x9, #1
    str     x9, [x21]
8:  mov     x0, #LANTERN_OK
    LEAVE 16
END_FUNCTION lantern_is_valid_switch_to_compounding_request

/* x19 state, x20 index. Locals: L the PendingDeposit (PendingDeposit__mem). */
FUNCTION lantern_queue_excess_active_balance
    ENTER 192
    mov     x19, x0
    ldr     x20, [x1]
    PART    x9, x10, x19, BeaconState_balances
    ldr     x11, [x9, x20, lsl #3]
    MOVQ    x12, MIN_ACTIVATION_BALANCE
    cmp     x11, x12
    b.ls    8f
    LDQ     x13, x19, BeaconState_pending_deposits      /* room first: the state must not change on failure */
    LDQ     x14, x19, BeaconState_pending_deposits + 8
    LDQ     x15, x19, BeaconState_pending_partial_withdrawals
    sub     x15, x15, x13
    add     x14, x14, #1
    mov     x13, #PendingDeposit__mem
    mul     x14, x14, x13
    cmp     x14, x15
    b.hi    9f
    sub     x13, x11, x12                   /* excess_balance */
    str     x13, [sp, #(L + PendingDeposit_amount)]
    str     x12, [x9, x20, lsl #3]          /* balances[index] = MIN_ACTIVATION_BALANCE */
    PART    x9, x10, x19, BeaconState_validators
    add     x9, x9, x20, lsl #7
    add     x0, sp, #(L + PendingDeposit_pubkey)
    add     x1, x9, #Validator_pubkey
    mov     x2, #(48 + 32)                  /* pubkey and withdrawal_credentials */
    bl      lantern_copy
    add     x0, sp, #(L + PendingDeposit_signature)     /* G2_POINT_AT_INFINITY */
    mov     x1, #96
    bl      lantern_zero
    mov     w9, #0xc0
    strb    w9, [sp, #(L + PendingDeposit_signature)]
    mov     x9, #GENESIS_SLOT
    str     x9, [sp, #(L + PendingDeposit_slot)]
    mov     x0, x19
    add     x1, sp, #L
    bl      append_pending_deposit
    LEAVE 192
8:  mov     x0, #LANTERN_OK
    LEAVE 192
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 192
END_FUNCTION lantern_queue_excess_active_balance

.if (Validator_withdrawal_credentials != Validator_pubkey + 48) || (PendingDeposit_withdrawal_credentials != PendingDeposit_pubkey + 48)
.error "lantern_queue_excess_active_balance copies pubkey and credentials together"
.endif

/* x19 state, x20 index pointer. */
FUNCTION lantern_switch_to_compounding_validator
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    LDQ     x13, x19, BeaconState_pending_deposits      /* room for the excess deposit, before any change */
    LDQ     x14, x19, BeaconState_pending_deposits + 8
    LDQ     x15, x19, BeaconState_pending_partial_withdrawals
    sub     x15, x15, x13
    add     x14, x14, #1
    mov     x13, #PendingDeposit__mem
    mul     x14, x14, x13
    cmp     x14, x15
    b.hi    9f
    ldr     x9, [x20]
    PART    x10, x11, x19, BeaconState_validators
    add     x10, x10, x9, lsl #7
    mov     w11, #COMPOUNDING_WITHDRAWAL_PREFIX
    strb    w11, [x10, #Validator_withdrawal_credentials]
    mov     x0, x19
    mov     x1, x20
    bl      lantern_queue_excess_active_balance
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_switch_to_compounding_validator

/*
 * x19 state, x20 balance, x21 config, x22 scratch, x23 out, x24 earliest, x25 churn,
 * x26 to consume, x27 result. Locals: L current epoch, L+8 activation exit epoch, L+16 churn.
 */
FUNCTION lantern_compute_consolidation_epoch_and_update_churn
    ENTER 32
    mov     x19, x0
    ldr     x20, [x1]
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x27, x5
    NEED_SCRATCH x22, x19, 1, 9f
    str     xzr, [x27]
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    add     x0, sp, #L
    add     x1, sp, #(L + 8)
    bl      lantern_compute_activation_exit_epoch
    LDQ     x9, x19, BeaconState_earliest_consolidation_epoch
    ldr     x10, [sp, #(L + 8)]
    cmp     x9, x10
    csel    x24, x9, x10, hi
    mov     x0, x19
    mov     x1, x21
    mov     x2, x22
    add     x3, sp, #(L + 16)
    bl      lantern_get_consolidation_churn_limit
    cbnz    x0, 7f
    ldr     x25, [sp, #(L + 16)]
    LDQ     x9, x19, BeaconState_earliest_consolidation_epoch
    LDQ     x26, x19, BeaconState_consolidation_balance_to_consume
    cmp     x9, x24
    csel    x26, x25, x26, lo
    cmp     x20, x26
    b.ls    1f
    cbz     x25, 6f                         /* the spec divides by the churn */
    sub     x9, x20, x26
    sub     x9, x9, #1
    udiv    x9, x9, x25
    add     x9, x9, #1
    adds    x24, x24, x9
    b.cs    6f
    mul     x10, x9, x25
    umulh   x11, x9, x25
    cbnz    x11, 6f
    adds    x26, x26, x10
    b.cs    6f
1:  sub     x26, x26, x20
    STQ     x26, x19, BeaconState_consolidation_balance_to_consume
    STQ     x24, x19, BeaconState_earliest_consolidation_epoch
    str     x24, [x23]
    mov     x0, #LANTERN_OK
7:  LEAVE 32
6:  mov     x9, #LANTERN_INVALID_OVERFLOW
    str     x9, [x27]
    mov     x0, #LANTERN_OK
    LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION lantern_compute_consolidation_epoch_and_update_churn

/*
 * x19 state, x20 request, x21 config, x22 scratch, x23 result, x24 source, x25 target,
 * x26 source index, x27 target index. Locals: L predicate, L+8 epoch, L+16 churn, L+24 pending,
 * L+32 index, L+40 exit epoch.
 */
FUNCTION lantern_process_consolidation_request
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    NEED_SCRATCH x22, x19, 1, 9f
    LDQ     x9, x19, BeaconState_pending_deposits       /* room: one pending deposit or one pending consolidation */
    LDQ     x10, x19, BeaconState_pending_deposits + 8
    LDQ     x11, x19, BeaconState_pending_partial_withdrawals
    sub     x11, x11, x9
    add     x10, x10, #1
    mov     x12, #PendingDeposit__mem
    mul     x10, x10, x12
    cmp     x10, x11
    b.hi    9f
    LDQ     x9, x19, BeaconState_pending_consolidations
    LDQ     x10, x19, BeaconState_pending_consolidations + 8
    ldr     x11, [x19]
    sub     x11, x11, x9
    add     x10, x10, #1
    lsl     x10, x10, #4
    cmp     x10, x11
    b.hi    9f
    str     xzr, [x23]
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #L
    bl      lantern_is_valid_switch_to_compounding_request
    ldr     x9, [sp, #L]
    cbz     x9, 1f
    mov     x0, x19                         /* switch_to_compounding_validator(state, source_index) */
    add     x1, x20, #ConsolidationRequest_source_pubkey
    bl      find_pubkey
    str     x0, [sp, #(L + 32)]
    mov     x0, x19
    add     x1, sp, #(L + 32)
    bl      lantern_switch_to_compounding_validator
    b       7f
1:  add     x14, x20, #ConsolidationRequest_source_pubkey   /* source_pubkey == target_pubkey: return */
    add     x15, x20, #ConsolidationRequest_target_pubkey
    ldp     x9, x10, [x14]
    ldp     x11, x12, [x15]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    2f
    ldp     x9, x10, [x14, #16]
    ldp     x11, x12, [x15, #16]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    2f
    ldp     x9, x10, [x14, #32]
    ldp     x11, x12, [x15, #32]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.eq    8f
2:  LDQ     x9, x19, BeaconState_pending_consolidations + 8
    MOVQ    x10, PENDING_CONSOLIDATIONS_LIMIT
    cmp     x9, x10
    b.eq    8f
    mov     x0, x19                         /* get_consolidation_churn_limit(state) <= MIN_ACTIVATION_BALANCE: return */
    mov     x1, x21
    mov     x2, x22
    add     x3, sp, #(L + 16)
    bl      lantern_get_consolidation_churn_limit
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 16)]
    MOVQ    x10, MIN_ACTIVATION_BALANCE
    cmp     x9, x10
    b.ls    8f
    mov     x0, x19
    add     x1, x20, #ConsolidationRequest_source_pubkey
    bl      find_pubkey
    cmn     x0, #1
    b.eq    8f
    mov     x26, x0
    mov     x0, x19
    add     x1, x20, #ConsolidationRequest_target_pubkey
    bl      find_pubkey
    cmn     x0, #1
    b.eq    8f
    mov     x27, x0
    PART    x24, x9, x19, BeaconState_validators
    add     x25, x24, x27, lsl #7
    add     x24, x24, x26, lsl #7
    mov     x0, x24
    add     x1, sp, #L
    bl      lantern_has_execution_withdrawal_credential
    ldr     x9, [sp, #L]
    cbz     x9, 8f
    add     x14, x20, #ConsolidationRequest_source_address
    SAME_ADDRESS x14, x24
    b.ne    8f
    mov     x0, x25
    add     x1, sp, #L
    bl      lantern_has_compounding_withdrawal_credential
    ldr     x9, [sp, #L]
    cbz     x9, 8f
    mov     x0, x19
    add     x1, sp, #(L + 8)
    bl      lantern_get_current_epoch
    mov     x0, x24
    add     x1, sp, #(L + 8)
    add     x2, sp, #L
    bl      lantern_is_active_validator
    ldr     x9, [sp, #L]
    cbz     x9, 8f
    mov     x0, x25
    add     x1, sp, #(L + 8)
    add     x2, sp, #L
    bl      lantern_is_active_validator
    ldr     x9, [sp, #L]
    cbz     x9, 8f
    ldr     x9, [x24, #Validator_exit_epoch]
    cmn     x9, #1
    b.ne    8f
    ldr     x9, [x25, #Validator_exit_epoch]
    cmn     x9, #1
    b.ne    8f
    ldr     x9, [x24, #Validator_activation_epoch]
    ldr     x10, [x21, #CONFIG_SHARD_COMMITTEE_PERIOD]
    adds    x9, x9, x10
    b.cs    5f
    ldr     x10, [sp, #(L + 8)]
    cmp     x10, x9
    b.lo    8f
    str     x26, [sp, #(L + 32)]
    mov     x0, x19
    add     x1, sp, #(L + 32)
    add     x2, sp, #(L + 24)
    bl      lantern_get_pending_balance_to_withdraw
    CHECK_STATUS x23, 7f, 8f
    ldr     x9, [sp, #(L + 24)]
    cbnz    x9, 8f
    mov     x0, x19                         /* source.exit_epoch = compute_consolidation_epoch_and_update_churn(...) */
    add     x1, x24, #Validator_effective_balance
    mov     x2, x21
    mov     x3, x22
    add     x4, sp, #(L + 40)
    mov     x5, x23
    bl      lantern_compute_consolidation_epoch_and_update_churn
    cbnz    x0, 7f
    ldr     x9, [x23]
    cbnz    x9, 8f
    ldr     x9, [sp, #(L + 40)]
    str     x9, [x24, #Validator_exit_epoch]
    ldr     x10, [x21, #CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY]
    adds    x9, x9, x10
    b.cs    5f
    str     x9, [x24, #Validator_withdrawable_epoch]
    PART    x9, x10, x19, BeaconState_pending_consolidations
    add     x9, x9, x10, lsl #4
    str     x26, [x9, #PendingConsolidation_source_index]
    str     x27, [x9, #PendingConsolidation_target_index]
    add     x10, x10, #1
    STQ     x10, x19, BeaconState_pending_consolidations + 8
8:  mov     x0, #LANTERN_OK
7:  LEAVE 48
5:  mov     x9, #LANTERN_INVALID_OVERFLOW
    str     x9, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
END_FUNCTION lantern_process_consolidation_request
