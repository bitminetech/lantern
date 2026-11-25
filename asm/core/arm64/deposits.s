/*
 * Deposits and the validator registry, ARM64. Requirements: docs/reference/block-processing.md
 * and docs/reference/epoch-processing.md.
 */

.if FORK >= FORK_ELECTRA
.if (PendingDeposit_pubkey != DepositData_pubkey) || (PendingDeposit_withdrawal_credentials != DepositData_withdrawal_credentials) || (PendingDeposit_amount != DepositData_amount) || (PendingDeposit_signature != DepositData_signature)
.error "PendingDeposit does not start with the DepositData layout"
.endif
.endif
.if (DepositMessage_pubkey != DepositData_pubkey) || (DepositMessage_withdrawal_credentials != DepositData_withdrawal_credentials) || (DepositMessage_amount != DepositData_amount)
.error "DepositData does not start with the DepositMessage layout"
.endif

/*
 * The lists that grow with each validator, as PartSpecs: PartRef, next PartRef (0: the
 * part ends at the end of the value), stride.
 */
.if FORK >= FORK_BELLATRIX
.set INACTIVITY_SCORES_NEXT, BeaconState_latest_execution_payload_header
.else
.set INACTIVITY_SCORES_NEXT, 0
.endif
.macro VALIDATOR_LISTS m
    \m part_validators, BeaconState_validators, BeaconState_balances, Validator__mem
.if FORK == FORK_PHASE0
    \m part_balances, BeaconState_balances, BeaconState_previous_epoch_attestations, 8
.else
    \m part_balances, BeaconState_balances, BeaconState_previous_epoch_participation, 8
    \m part_previous_epoch_participation, BeaconState_previous_epoch_participation, BeaconState_current_epoch_participation, 1
    \m part_current_epoch_participation, BeaconState_current_epoch_participation, BeaconState_inactivity_scores, 1
    \m part_inactivity_scores, BeaconState_inactivity_scores, INACTIVITY_SCORES_NEXT, 8
.endif
.endm

.macro PART_SPEC label, ref, next, stride
\label:
    .quad \ref, \next, \stride
.endm

    RODATA
    .p2align 3
VALIDATOR_LISTS PART_SPEC

/* x9 = min(x9, free entries of one list of state x0). Uses x10-x13, x16. */
.macro LIST_ROOM label, ref, next, stride
    LDQ     x10, x0, \ref
    LDQ     x11, x0, (\ref) + 8
    .if \next
    LDQ     x12, x0, \next
    .else
    ldr     x12, [x0]                       /* the last part ends at the end of the value */
    .endif
    sub     x12, x12, x10
    .if \stride > 1
    mov     x13, #\stride
    udiv    x12, x12, x13
    .endif
    sub     x12, x12, x11
    cmp     x12, x9
    csel    x9, x12, x9, lo
.endm

/* L0: x0 = the fewest free entries in the validator lists of state x0. */
LOCAL_FUNCTION lantern_validator_room
    UNWIND_END_PROLOGUE
    mov     x9, #-1
    VALIDATOR_LISTS LIST_ROOM
    mov     x0, x9
    ret
END_FUNCTION lantern_validator_room

/* L0: x0 = the index of the validator of state x0 with the 48-byte public key at x1, or -1. */
LOCAL_FUNCTION lantern_find_pubkey
    UNWIND_END_PROLOGUE
    PART    x9, x10, x0, BeaconState_validators
    ldp     x2, x3, [x1]
    ldp     x4, x5, [x1, #16]
    ldp     x6, x7, [x1, #32]
    mov     x11, #0
1:  cmp     x11, x10
    b.hs    3f
    ldp     x12, x13, [x9, #Validator_pubkey]
    cmp     x12, x2
    ccmp    x13, x3, #0, eq
    b.ne    2f
    ldp     x12, x13, [x9, #(Validator_pubkey + 16)]
    cmp     x12, x4
    ccmp    x13, x5, #0, eq
    b.ne    2f
    ldp     x12, x13, [x9, #(Validator_pubkey + 32)]
    cmp     x12, x6
    ccmp    x13, x7, #0, eq
    b.ne    2f
    mov     x0, x11
    ret
2:  add     x9, x9, #Validator__mem
    add     x11, x11, #1
    b       1b
3:  mov     x0, #-1
    ret
END_FUNCTION lantern_find_pubkey

/*
 * x19 deposit, x20 config, x21 scratch, x22 out. Locals: L domain type, L+8 zero root,
 * L+40 domain, L+72 the signing root as a ByteList (header 24, then 32 bytes).
 */
SPEC_FUNCTION_FROM FORK_ELECTRA, is_valid_deposit_signature
    ENTER 128
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     w9, #DOMAIN_DEPOSIT
    str     w9, [sp, #L]
    stp     xzr, xzr, [sp, #(L + 8)]
    stp     xzr, xzr, [sp, #(L + 24)]
    add     x0, sp, #L                      /* domain = compute_domain(DOMAIN_DEPOSIT) */
    add     x1, x20, #CONFIG_GENESIS_FORK_VERSION
    add     x2, sp, #(L + 8)
    mov     x3, x21
    add     x4, sp, #(L + 40)
    bl      lantern_compute_domain
    cbnz    x0, 7f
    ADDRESS x0, lantern_type_DepositMessage /* signing_root = compute_signing_root(deposit_message, domain) */
    mov     x1, x19
    add     x2, sp, #(L + 40)
    mov     x3, x21
    add     x4, sp, #(L + 96)
    bl      lantern_compute_signing_root
    cbnz    x0, 7f
    mov     x9, #56
    str     x9, [sp, #(L + 72)]
    mov     x9, #24
    str     x9, [sp, #(L + 80)]
    mov     x9, #32
    str     x9, [sp, #(L + 88)]
    add     x0, x19, #DepositData_pubkey    /* bls.Verify(pubkey, signing_root, signature) */
    add     x1, sp, #(L + 72)
    add     x2, x19, #DepositData_signature
    mov     x3, x21
    mov     x4, x22
    CALL_GLOBAL crypto_bls_verify
7:  LEAVE 128
SPEC_END_FROM FORK_ELECTRA, is_valid_deposit_signature

/* x19 out, x20 amount. Locals: L max effective balance. */
SPEC_FUNCTION get_validator_from_deposit
    ENTER 16
    mov     x19, x3
    mov     x20, x2
    ldp     x9, x10, [x0]
    stp     x9, x10, [x19, #Validator_pubkey]
    ldp     x9, x10, [x0, #16]
    stp     x9, x10, [x19, #(Validator_pubkey + 16)]
    ldp     x9, x10, [x0, #32]
    stp     x9, x10, [x19, #(Validator_pubkey + 32)]
    add     x9, x19, #Validator_withdrawal_credentials
    COPY32  x9, x1
    str     xzr, [x19, #Validator_effective_balance]
    str     xzr, [x19, #Validator_slashed]  /* slashed, and the padding after it */
    mov     x9, #FAR_FUTURE_EPOCH
    str     x9, [x19, #Validator_activation_eligibility_epoch]
    str     x9, [x19, #Validator_activation_epoch]
    str     x9, [x19, #Validator_exit_epoch]
    str     x9, [x19, #Validator_withdrawable_epoch]
.if FORK >= FORK_ELECTRA
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_max_effective_balance
.else
    MOVQ    x9, MAX_EFFECTIVE_BALANCE
    str     x9, [sp, #L]
.endif
    ldr     x9, [x20]
    MOVQ    x10, EFFECTIVE_BALANCE_INCREMENT
    udiv    x11, x9, x10
    mul     x11, x11, x10                   /* amount - amount % EFFECTIVE_BALANCE_INCREMENT */
    ldr     x12, [sp, #L]
    cmp     x11, x12
    csel    x11, x11, x12, lo
    str     x11, [x19, #Validator_effective_balance]
    mov     x0, #LANTERN_OK
    LEAVE 16
SPEC_END get_validator_from_deposit

.if Validator_slashed != 88 || Validator_activation_eligibility_epoch != 96
.error "lantern_get_validator_from_deposit zeroes slashed and its padding with one 8-byte store"
.endif

SPEC_LEAF_FROM FORK_ALTAIR, get_index_for_new_validator
    LDQ     x2, x0, BeaconState_validators + 8
    str     x2, [x1]
    RETURN_OK
SPEC_END_FROM FORK_ALTAIR, get_index_for_new_validator

/* x19 state, x20 the entry, x21 stride, x22 value. Phase0 appends with it too. */
SPEC_FUNCTION_FROM FORK_ALTAIR, set_or_append_list
    ENTER 16
    mov     x19, x0
    mov     x22, x3
    ldr     x9, [x1]                        /* ref */
    ldr     x10, [x1, #8]                   /* next */
    ldr     x21, [x1, #16]                  /* stride */
    ldr     x11, [x19, x9]                  /* part offset */
    add     x12, x9, #8
    ldr     x13, [x19, x12]                 /* count */
    ldr     x14, [x2]                       /* index */
    cmp     x14, x13
    b.ne    1f
    ldr     x15, [x19]                      /* append: the part ends where the next starts */
    cbz     x10, 2f
    ldr     x15, [x19, x10]
2:  sub     x15, x15, x11
    add     x17, x13, #1
    mul     x17, x17, x21
    cmp     x17, x15
    b.hi    9f
    add     x17, x13, #1
    str     x17, [x19, x12]
1:  madd    x20, x14, x21, x11
    add     x20, x19, x20
    mov     x0, x20
    mov     x1, x22
    mov     x2, x21
    bl      lantern_copy
    mov     x0, #LANTERN_OK
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END_FROM FORK_ALTAIR, set_or_append_list

/*
 * x19 state, x20 pubkey, x21 withdrawal credentials, x22 amount.
 * Locals: L the validator (128), L+128 index, L+136 zero.
 */
SPEC_FUNCTION add_validator_to_registry
    ENTER 144
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x0, x19
    bl      lantern_validator_room
    cbz     x0, 9f
    mov     x0, x19
    add     x1, sp, #(L + 128)
    bl      lantern_get_index_for_new_validator
    mov     x0, x20
    mov     x1, x21
    mov     x2, x22
    add     x3, sp, #L
    bl      lantern_get_validator_from_deposit
    str     xzr, [sp, #(L + 136)]
    mov     x0, x19
    ADDRESS x1, part_validators
    add     x2, sp, #(L + 128)
    add     x3, sp, #L
    bl      lantern_set_or_append_list
    mov     x0, x19
    ADDRESS x1, part_balances
    add     x2, sp, #(L + 128)
    mov     x3, x22
    bl      lantern_set_or_append_list
.if FORK >= FORK_ALTAIR
    mov     x0, x19
    ADDRESS x1, part_previous_epoch_participation
    add     x2, sp, #(L + 128)
    add     x3, sp, #(L + 136)
    bl      lantern_set_or_append_list
    mov     x0, x19
    ADDRESS x1, part_current_epoch_participation
    add     x2, sp, #(L + 128)
    add     x3, sp, #(L + 136)
    bl      lantern_set_or_append_list
    mov     x0, x19
    ADDRESS x1, part_inactivity_scores
    add     x2, sp, #(L + 128)
    add     x3, sp, #(L + 136)
    bl      lantern_set_or_append_list
.endif
    mov     x0, #LANTERN_OK
    LEAVE 144
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 144
SPEC_END add_validator_to_registry

.if FORK <= FORK_ELECTRA
.if FORK == FORK_ELECTRA
/*
 * The deposit's (pubkey, withdrawal_credentials, amount, signature) are the fields of the
 * DepositData at x1. x19 state, x20 data, x21 config, x22 scratch.
 * Locals: L zero amount, L+8 valid, L+16 the PendingDeposit.
 */
SPEC_FUNCTION apply_deposit
    ENTER 208
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    LDQ     x10, x19, BeaconState_pending_deposits      /* room for the PendingDeposit, before any change */
    LDQ     x11, x19, BeaconState_pending_deposits + 8
    LDQ     x12, x19, BeaconState_pending_partial_withdrawals
    sub     x12, x12, x10
    add     x13, x11, #1
    mov     x14, #PendingDeposit__mem
    mul     x13, x13, x14
    cmp     x13, x12
    b.hi    9f
    mov     x0, x19                         /* if pubkey not in validator_pubkeys */
    add     x1, x20, #DepositData_pubkey
    bl      lantern_find_pubkey
    cmn     x0, #1
    b.ne    5f
    mov     x0, x19                         /* room for the validator, before any change */
    bl      lantern_validator_room
    cbz     x0, 9f
    mov     x0, x20
    mov     x1, x21
    mov     x2, x22
    add     x3, sp, #(L + 8)
    bl      lantern_is_valid_deposit_signature
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 8)]
    cbz     x9, 8f                          /* an invalid signature: the deposit is skipped */
    str     xzr, [sp, #L]
    mov     x0, x19                         /* add_validator_to_registry(state, pubkey, withdrawal_credentials, Gwei(0)) */
    add     x1, x20, #DepositData_pubkey
    add     x2, x20, #DepositData_withdrawal_credentials
    add     x3, sp, #L
    bl      lantern_add_validator_to_registry
    cbnz    x0, 7f
5:  add     x0, sp, #(L + 16)               /* state.pending_deposits.append(PendingDeposit(..., slot=GENESIS_SLOT)) */
    mov     x1, x20
    mov     x2, #DepositData__mem
    bl      lantern_copy
    str     xzr, [sp, #(L + 16 + PendingDeposit_slot)]
    mov     x0, x19
    add     x1, sp, #(L + 16)
    bl      lantern_append_pending_deposit
    b       7f
8:  mov     x0, #LANTERN_OK
7:  LEAVE 208
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 208
SPEC_END apply_deposit
.if (PendingDeposit_slot != DepositData__mem) || (PendingDeposit__mem > 192)
.error "apply_deposit copies a DepositData into the first fields of a PendingDeposit"
.endif
.else
/*
 * The deposit's (pubkey, withdrawal_credentials, amount, signature) are the fields of the
 * DepositData at x1. x19 state, x20 data, x21 config, x22 scratch, x23 scratch size.
 * Locals: L index, L+8 valid.
 */
SPEC_FUNCTION apply_deposit
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    ldr     x23, [x22]
    mov     x0, x19                         /* if pubkey not in validator_pubkeys */
    add     x1, x20, #DepositData_pubkey
    bl      lantern_find_pubkey
    cmn     x0, #1
    b.ne    5f
    mov     x0, x19                         /* room for the validator, before any change */
    bl      lantern_validator_room
    cbz     x0, 9f
    mov     x0, x20
    mov     x1, x21
    mov     x2, x22
    add     x3, sp, #(L + 8)
    bl      lantern_is_valid_deposit_signature
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 8)]
    cbz     x9, 8f                          /* an invalid signature: the deposit is skipped */
    mov     x0, x19
    add     x1, x20, #DepositData_pubkey
    add     x2, x20, #DepositData_withdrawal_credentials
    add     x3, x20, #DepositData_amount
    bl      lantern_add_validator_to_registry
    b       7f
5:  str     x0, [sp, #L]                    /* else increase_balance(state, index, amount) */
    mov     x0, x19
    add     x1, sp, #L
    add     x2, x20, #DepositData_amount
    bl      lantern_increase_balance
8:  mov     x0, #LANTERN_OK
7:  LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END apply_deposit
.endif

/*
 * x19 state, x20 deposit, x21 config, x22 scratch, x23 result, x24 scratch size.
 * Locals: L leaf (32), L+32 depth, L+40 index, L+48 valid.
 */
SPEC_FUNCTION process_deposit
    ENTER 64
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    str     xzr, [x23]
    ldr     x24, [x22]
    mov     x0, x19                         /* room for a new validator, before any change */
    bl      lantern_validator_room
    cbz     x0, 9f
    ADDRESS x0, lantern_type_DepositData    /* leaf = hash_tree_root(deposit.data) */
    add     x1, x20, #Deposit_data
    mov     x2, x22
    add     x3, sp, #L
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    mov     x9, #(DEPOSIT_CONTRACT_TREE_DEPTH + 1)
    str     x9, [sp, #(L + 32)]
    LDQ     x9, x19, BeaconState_eth1_deposit_index
    str     x9, [sp, #(L + 40)]
    add     x0, sp, #L                      /* assert is_valid_merkle_branch(...) */
    add     x1, x20, #Deposit_proof
    add     x2, sp, #(L + 32)
    add     x3, sp, #(L + 40)
    ADDQ    x4, x19, BeaconState_eth1_data + Eth1Data_deposit_root
    add     x5, sp, #(L + 48)
    bl      lantern_is_valid_merkle_branch
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 48)]
    mov     x10, #LANTERN_INVALID_DEPOSIT
    cbz     x9, 6f
    LDQ     x9, x19, BeaconState_eth1_deposit_index     /* state.eth1_deposit_index += 1 */
    adds    x9, x9, #1
    mov     x10, #LANTERN_INVALID_OVERFLOW
    b.cs    6f
    STQ     x9, x19, BeaconState_eth1_deposit_index
    str     x24, [x22]
    mov     x0, x19
    add     x1, x20, #Deposit_data
    mov     x2, x21
    mov     x3, x22
    bl      lantern_apply_deposit
7:  LEAVE 64
6:  str     x10, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 64
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
SPEC_END process_deposit
.endif

.if FORK >= FORK_ELECTRA
/* x19 state, x20 deposit, x21 config, x22 scratch. Locals: L valid, L+8 index. */
SPEC_FUNCTION apply_pending_deposit
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x0, x19
    add     x1, x20, #PendingDeposit_pubkey
    bl      lantern_find_pubkey
    cmn     x0, #1
    b.ne    1f
    mov     x0, x20                         /* a new public key: a validator when the signature is valid */
    mov     x1, x21
    mov     x2, x22
    add     x3, sp, #L
    bl      lantern_is_valid_deposit_signature
    cbnz    x0, 7f
    ldr     x9, [sp, #L]
    cbz     x9, 8f
    mov     x0, x19
    add     x1, x20, #PendingDeposit_pubkey
    add     x2, x20, #PendingDeposit_withdrawal_credentials
    add     x3, x20, #PendingDeposit_amount
    bl      lantern_add_validator_to_registry
    b       7f
1:  str     x0, [sp, #(L + 8)]              /* increase_balance(state, validator_index, deposit.amount) */
    mov     x0, x19
    add     x1, sp, #(L + 8)
    add     x2, x20, #PendingDeposit_amount
    bl      lantern_increase_balance
8:  mov     x0, #LANTERN_OK
7:  LEAVE 16
SPEC_END apply_pending_deposit
.endif

.if FORK >= FORK_ELECTRA
.set POSTPONE_BYTES, MAX_PENDING_DEPOSITS_PER_EPOCH * PendingDeposit__mem
.endif

.if FORK >= FORK_ELECTRA
/*
 * x19 state, x20 config, x21 scratch, x22 result, x23 scratch size, x24 postponed,
 * x25 available, x26 processed, x27 next deposit index, x28 postponed count.
 * Locals: L current epoch, L+8 next epoch, L+16 churn, L+24 reached, L+32 finalized slot,
 * L+40 the deposit (PendingDeposit__mem bytes).
 */
SPEC_FUNCTION process_pending_deposits
    ENTER 240
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    NEED_SCRATCH_B x21, x19, 1, POSTPONE_BYTES, 9f
    mov     x0, x19
    bl      lantern_validator_room
    cmp     x0, #MAX_PENDING_DEPOSITS_PER_EPOCH
    b.lo    9f
    str     xzr, [x22]
    ldr     x23, [x21]
    MOVQ    x9, POSTPONE_BYTES
    sub     x9, x23, x9
    add     x24, x21, x9                    /* deposits_to_postpone: at the end of scratch */
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x9, [sp, #L]
    add     x9, x9, #1
    str     x9, [sp, #(L + 8)]
    MOVQ    x9, POSTPONE_BYTES              /* available_for_processing */
    sub     x9, x23, x9
    str     x9, [x21]
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    add     x3, sp, #(L + 16)
    bl      lantern_get_activation_exit_churn_limit
    cbnz    x0, 7f
    LDQ     x9, x19, BeaconState_deposit_balance_to_consume
    ldr     x10, [sp, #(L + 16)]
    adds    x25, x9, x10
    b.cs    6f
    mov     x26, #0
    mov     x27, #0
    mov     x28, #0
    str     xzr, [sp, #(L + 24)]
    ADDQ    x0, x19, BeaconState_finalized_checkpoint + Checkpoint_epoch
    add     x1, sp, #(L + 32)
    bl      lantern_compute_start_slot_at_epoch
    cbnz    x0, 5f
1:  PART    x9, x10, x19, BeaconState_pending_deposits
    cmp     x27, x10                        /* for deposit in state.pending_deposits */
    b.hs    4f
    mov     x11, #PendingDeposit__mem
    madd    x9, x27, x11, x9
    ldr     x10, [x9, #PendingDeposit_slot]
.if FORK == FORK_ELECTRA
    cbz     x10, 11f                        /* a deposit request (slot > GENESIS_SLOT) */
    LDQ     x11, x19, BeaconState_eth1_deposit_index
    LDQ     x12, x19, BeaconState_deposit_requests_start_index
    cmp     x11, x12                        /* while Eth1 bridge deposits are pending */
    b.lo    4f
11:
.endif
    ldr     x11, [sp, #(L + 32)]
    cmp     x10, x11                        /* a deposit not yet finalized */
    b.hi    4f
    cmp     x27, #MAX_PENDING_DEPOSITS_PER_EPOCH
    b.hs    4f
    add     x0, sp, #(L + 40)               /* a copy of the deposit, apart from the state */
    mov     x1, x9
    mov     x2, #PendingDeposit__mem
    bl      lantern_copy
    mov     x0, x19
    add     x1, sp, #(L + 40 + PendingDeposit_pubkey)
    bl      lantern_find_pubkey
    cmn     x0, #1
    b.eq    3f                              /* not exited, not withdrawn */
    PART    x9, x10, x19, BeaconState_validators
    add     x9, x9, x0, lsl #7
    ldr     x10, [x9, #Validator_withdrawable_epoch]
    ldr     x11, [sp, #(L + 8)]
    cmp     x10, x11
    b.lo    2f                              /* withdrawn: apply */
    ldr     x10, [x9, #Validator_exit_epoch]
    cmn     x10, #1
    b.eq    3f
    mov     x9, #PendingDeposit__mem        /* exited: postpone */
    madd    x0, x28, x9, x24
    add     x1, sp, #(L + 40)
    mov     x2, #PendingDeposit__mem
    bl      lantern_copy
    add     x28, x28, #1
    b       25f
3:  ldr     x9, [sp, #(L + 40 + PendingDeposit_amount)]
    adds    x9, x26, x9                     /* is_churn_limit_reached = processed_amount + deposit.amount > available */
    b.cs    6f
    cmp     x9, x25
    b.hi    35f
    mov     x26, x9
2:  MOVQ    x9, POSTPONE_BYTES
    sub     x9, x23, x9
    str     x9, [x21]
    mov     x0, x19
    add     x1, sp, #(L + 40)
    mov     x2, x20
    mov     x3, x21
    bl      lantern_apply_pending_deposit
    cbnz    x0, 7f
25: add     x27, x27, #1
    b       1b
35: mov     x9, #1
    str     x9, [sp, #(L + 24)]
4:  PART    x0, x10, x19, BeaconState_pending_deposits  /* pending_deposits[next_deposit_index:] + deposits_to_postpone */
    sub     x9, x10, x27
    str     x9, [sp, #(L + 232)]            /* the entries kept */
    mov     x11, #PendingDeposit__mem
    mul     x2, x9, x11
    madd    x1, x27, x11, x0
    bl      lantern_copy
    PART    x0, x10, x19, BeaconState_pending_deposits
    ldr     x9, [sp, #(L + 232)]
    mov     x11, #PendingDeposit__mem
    madd    x0, x9, x11, x0
    mov     x1, x24
    mul     x2, x28, x11
    bl      lantern_copy
    ldr     x9, [sp, #(L + 232)]
    add     x9, x9, x28
    STQ     x9, x19, BeaconState_pending_deposits + 8
    ldr     x9, [sp, #(L + 24)]             /* deposit_balance_to_consume */
    mov     x10, #0
    cbz     x9, 45f
    sub     x10, x25, x26                   /* available_for_processing - processed_amount */
45: STQ     x10, x19, BeaconState_deposit_balance_to_consume
    b       8f
5:  mov     x0, #LANTERN_OK                 /* the finalized slot leaves the Uint64 range */
6:  mov     x9, #LANTERN_INVALID_OVERFLOW
    str     x9, [x22]
8:  mov     x0, #LANTERN_OK
7:  LEAVE 240
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 240
SPEC_END process_pending_deposits
.endif
