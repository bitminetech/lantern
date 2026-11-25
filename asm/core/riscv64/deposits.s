/*
 * Deposits and the validator registry, RISC-V. Requirements: docs/reference/block-processing.md
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

/* t0 = min(t0, free entries of one list of state a0). A next of 0 reads the value's size, where the last part ends. Uses t1-t4, a7. */
.macro LIST_ROOM label, ref, next, stride
    LDQ     t1, a0, \ref
    LDQ     t2, a0, (\ref) + 8
    LDQ     t3, a0, \next
    sub     t3, t3, t1
    .if \stride == 128
    srli    t3, t3, 7
    .elseif \stride == 8
    srli    t3, t3, 3
    .elseif \stride > 1
    li      t4, \stride
    divu    t3, t3, t4
    .endif
    sub     t3, t3, t2
    bgeu    t3, t0, 1f
    mv      t0, t3
1:
.endm

/* L0: a0 = the fewest free entries in the validator lists of state a0. */
LOCAL_FUNCTION lantern_validator_room
    UNWIND_END_PROLOGUE
    li      t0, -1
    VALIDATOR_LISTS LIST_ROOM
    mv      a0, t0
    ret
END_FUNCTION lantern_validator_room

/*
 * L0: a0 = the index of the validator of state a0 with the 48-byte public key at a1, or -1.
 * The key is 4-aligned: request keys sit at offset 20 and 68.
 */
LOCAL_FUNCTION lantern_find_pubkey
    UNWIND_END_PROLOGUE
    PART    t0, t1, a0, BeaconState_validators
    LDU64   a2, a1, 0, t2
    LDU64   a3, a1, 8, t2
    LDU64   a4, a1, 16, t2
    LDU64   a5, a1, 24, t2
    LDU64   t5, a1, 32, t2
    LDU64   t6, a1, 40, t2
    li      t2, 0
1:  bgeu    t2, t1, 3f
    ld      t3, (Validator_pubkey)(t0)
    bne     t3, a2, 2f
    ld      t3, (Validator_pubkey + 8)(t0)
    bne     t3, a3, 2f
    ld      t3, (Validator_pubkey + 16)(t0)
    bne     t3, a4, 2f
    ld      t3, (Validator_pubkey + 24)(t0)
    bne     t3, a5, 2f
    ld      t3, (Validator_pubkey + 32)(t0)
    bne     t3, t5, 2f
    ld      t3, (Validator_pubkey + 40)(t0)
    bne     t3, t6, 2f
    mv      a0, t2
    ret
2:  addi    t0, t0, Validator__mem
    addi    t2, t2, 1
    j       1b
3:  li      a0, -1
    ret
END_FUNCTION lantern_find_pubkey

/*
 * s1 deposit, s2 config, s3 scratch, s4 out. Locals: L domain type, L+8 zero root,
 * L+40 domain, L+72 the signing root as a ByteList (header 24, then 32 bytes).
 */
SPEC_FUNCTION_FROM FORK_ELECTRA, is_valid_deposit_signature
    ENTER 128
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    li      t0, DOMAIN_DEPOSIT
    sw      t0, L(sp)
    sd      zero, (L + 8)(sp)
    sd      zero, (L + 16)(sp)
    sd      zero, (L + 24)(sp)
    sd      zero, (L + 32)(sp)
    addi    a0, sp, L                       # domain = compute_domain(DOMAIN_DEPOSIT)
    addi    a1, s2, CONFIG_GENESIS_FORK_VERSION
    addi    a2, sp, (L + 8)
    mv      a3, s3
    addi    a4, sp, (L + 40)
    call    lantern_compute_domain
    bnez    a0, 7f
    ADDRESS a0, lantern_type_DepositMessage # signing_root = compute_signing_root(deposit_message, domain)
    mv      a1, s1
    addi    a2, sp, (L + 40)
    mv      a3, s3
    addi    a4, sp, (L + 96)
    call    lantern_compute_signing_root
    bnez    a0, 7f
    li      t0, 56
    sd      t0, (L + 72)(sp)
    li      t0, 24
    sd      t0, (L + 80)(sp)
    li      t0, 32
    sd      t0, (L + 88)(sp)
    addi    a0, s1, DepositData_pubkey      # bls.Verify(pubkey, signing_root, signature)
    addi    a1, sp, (L + 72)
    addi    a2, s1, DepositData_signature
    mv      a3, s3
    mv      a4, s4
    CALL_GLOBAL crypto_bls_verify
7:  LEAVE 128
SPEC_END_FROM FORK_ELECTRA, is_valid_deposit_signature

/* s1 out, s2 amount. Locals: L max effective balance. The public key and credentials are 8-aligned. */
SPEC_FUNCTION get_validator_from_deposit
    ENTER 16
    mv      s1, a3
    mv      s2, a2
    .irp k, 0, 8, 16, 24, 32, 40
    ld      t0, \k(a0)
    sd      t0, (Validator_pubkey + \k)(s1)
    .endr
    addi    t0, s1, Validator_withdrawal_credentials
    COPY32  t0, a1
    sd      zero, Validator_effective_balance(s1)
    sd      zero, Validator_slashed(s1)     # slashed, and the padding after it
    li      t0, FAR_FUTURE_EPOCH
    sd      t0, Validator_activation_eligibility_epoch(s1)
    sd      t0, Validator_activation_epoch(s1)
    sd      t0, Validator_exit_epoch(s1)
    sd      t0, Validator_withdrawable_epoch(s1)
.if FORK >= FORK_ELECTRA
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_max_effective_balance
.else
    li      t0, MAX_EFFECTIVE_BALANCE
    sd      t0, L(sp)
.endif
    ld      t0, 0(s2)
    li      t1, EFFECTIVE_BALANCE_INCREMENT
    divu    t2, t0, t1
    mul     t2, t2, t1                      # amount - amount % EFFECTIVE_BALANCE_INCREMENT
    ld      t3, L(sp)
    bltu    t2, t3, 1f
    mv      t2, t3
1:  sd      t2, Validator_effective_balance(s1)
    li      a0, LANTERN_OK
    LEAVE 16
SPEC_END get_validator_from_deposit

.if Validator_slashed != 88 || Validator_activation_eligibility_epoch != 96
.error "lantern_get_validator_from_deposit zeroes slashed and its padding with one 8-byte store"
.endif

SPEC_LEAF_FROM FORK_ALTAIR, get_index_for_new_validator
    LDQ     a2, a0, BeaconState_validators + 8
    sd      a2, 0(a1)
    RETURN_OK
SPEC_END_FROM FORK_ALTAIR, get_index_for_new_validator

/* s1 state, s2 the entry, s3 stride, s4 value. */
SPEC_FUNCTION_FROM FORK_ALTAIR, set_or_append_list
    ENTER 16
    mv      s1, a0
    mv      s4, a3
    ld      t0, 0(a1)                       # ref
    ld      t1, 8(a1)                       # next
    ld      s3, 16(a1)                      # stride
    add     t2, s1, t0
    ld      t3, 0(t2)                       # part offset
    ld      t4, 8(t2)                       # count
    ld      t5, 0(a2)                       # index
    bne     t5, t4, 1f
    ld      t6, 0(s1)                       # append: the part ends where the next starts
    beqz    t1, 2f
    add     t6, s1, t1
    ld      t6, 0(t6)
2:  sub     t6, t6, t3
    addi    a4, t4, 1
    mul     a4, a4, s3
    bgtu    a4, t6, 9f
    addi    a4, t4, 1
    sd      a4, 8(t2)
1:  mul     s2, t5, s3
    add     s2, s2, t3
    add     s2, s1, s2
    mv      a0, s2
    mv      a1, s4
    mv      a2, s3
    call    lantern_copy
    li      a0, LANTERN_OK
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END_FROM FORK_ALTAIR, set_or_append_list

/*
 * s1 state, s2 pubkey, s3 withdrawal credentials, s4 amount.
 * Locals: L the validator (128), L+128 index, L+136 zero.
 */
SPEC_FUNCTION add_validator_to_registry
    ENTER 144
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      a0, s1
    call    lantern_validator_room
    beqz    a0, 9f
    mv      a0, s1
    addi    a1, sp, (L + 128)
    call    lantern_get_index_for_new_validator
    mv      a0, s2
    mv      a1, s3
    mv      a2, s4
    addi    a3, sp, L
    call    lantern_get_validator_from_deposit
    sd      zero, (L + 136)(sp)
    mv      a0, s1
    ADDRESS a1, part_validators
    addi    a2, sp, (L + 128)
    addi    a3, sp, L
    call    lantern_set_or_append_list
    mv      a0, s1
    ADDRESS a1, part_balances
    addi    a2, sp, (L + 128)
    mv      a3, s4
    call    lantern_set_or_append_list
.if FORK >= FORK_ALTAIR
    mv      a0, s1
    ADDRESS a1, part_previous_epoch_participation
    addi    a2, sp, (L + 128)
    addi    a3, sp, (L + 136)
    call    lantern_set_or_append_list
    mv      a0, s1
    ADDRESS a1, part_current_epoch_participation
    addi    a2, sp, (L + 128)
    addi    a3, sp, (L + 136)
    call    lantern_set_or_append_list
    mv      a0, s1
    ADDRESS a1, part_inactivity_scores
    addi    a2, sp, (L + 128)
    addi    a3, sp, (L + 136)
    call    lantern_set_or_append_list
.endif
    li      a0, LANTERN_OK
    LEAVE 144
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 144
SPEC_END add_validator_to_registry

.if FORK <= FORK_ELECTRA
.if FORK == FORK_ELECTRA
/*
 * The deposit's (pubkey, withdrawal_credentials, amount, signature) are the fields of the
 * DepositData at a1. s1 state, s2 data, s3 config, s4 scratch.
 * Locals: L zero amount, L+8 valid, L+16 the PendingDeposit.
 */
SPEC_FUNCTION apply_deposit
    ENTER 208
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    LDQ     t1, s1, BeaconState_pending_deposits    # room for the PendingDeposit, before any change
    LDQ     t2, s1, BeaconState_pending_deposits + 8
    LDQ     t3, s1, BeaconState_pending_partial_withdrawals
    sub     t3, t3, t1
    addi    t2, t2, 1
    li      t4, PendingDeposit__mem
    mul     t2, t2, t4
    bgtu    t2, t3, 9f
    mv      a0, s1
    addi    a1, s2, DepositData_pubkey      # if pubkey not in validator_pubkeys
    call    lantern_find_pubkey
    li      t0, -1
    bne     a0, t0, 5f
    mv      a0, s1                          # room for the validator, before any change
    call    lantern_validator_room
    beqz    a0, 9f
    mv      a0, s2
    mv      a1, s3
    mv      a2, s4
    addi    a3, sp, (L + 8)
    call    lantern_is_valid_deposit_signature
    bnez    a0, 7f
    ld      t0, (L + 8)(sp)
    beqz    t0, 8f                          # an invalid signature: the deposit is skipped
    sd      zero, L(sp)
    mv      a0, s1                          # add_validator_to_registry(state, pubkey, withdrawal_credentials, Gwei(0))
    addi    a1, s2, DepositData_pubkey
    addi    a2, s2, DepositData_withdrawal_credentials
    addi    a3, sp, L
    call    lantern_add_validator_to_registry
    bnez    a0, 7f
5:  addi    a0, sp, (L + 16)                # state.pending_deposits.append(PendingDeposit(..., slot=GENESIS_SLOT))
    mv      a1, s2
    li      a2, DepositData__mem
    call    lantern_copy
    sd      zero, (L + 16 + PendingDeposit_slot)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 16)
    call    lantern_append_pending_deposit
    j       7f
8:  li      a0, LANTERN_OK
7:  LEAVE 208
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 208
SPEC_END apply_deposit
.if (PendingDeposit_slot != DepositData__mem) || (PendingDeposit__mem > 192)
.error "apply_deposit copies a DepositData into the first fields of a PendingDeposit"
.endif
.else
/*
 * The deposit's (pubkey, withdrawal_credentials, amount, signature) are the fields of the
 * DepositData at a1. s1 state, s2 data, s3 config, s4 scratch. Locals: L index, L+8 valid.
 */
SPEC_FUNCTION apply_deposit
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    addi    a1, s2, DepositData_pubkey      # if pubkey not in validator_pubkeys
    call    lantern_find_pubkey
    li      t0, -1
    bne     a0, t0, 5f
    mv      a0, s1                          # room for the validator, before any change
    call    lantern_validator_room
    beqz    a0, 9f
    mv      a0, s2
    mv      a1, s3
    mv      a2, s4
    addi    a3, sp, (L + 8)
    call    lantern_is_valid_deposit_signature
    bnez    a0, 7f
    ld      t0, (L + 8)(sp)
    beqz    t0, 8f                          # an invalid signature: the deposit is skipped
    mv      a0, s1
    addi    a1, s2, DepositData_pubkey
    addi    a2, s2, DepositData_withdrawal_credentials
    addi    a3, s2, DepositData_amount
    call    lantern_add_validator_to_registry
    j       7f
5:  sd      a0, L(sp)                       # else increase_balance(state, index, amount)
    mv      a0, s1
    addi    a1, sp, L
    addi    a2, s2, DepositData_amount
    call    lantern_increase_balance
8:  li      a0, LANTERN_OK
7:  LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END apply_deposit
.endif

/*
 * s1 state, s2 deposit, s3 config, s4 scratch, s5 result, s6 scratch size.
 * Locals: L leaf (32), L+32 depth, L+40 index, L+48 valid.
 */
SPEC_FUNCTION process_deposit
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    sd      zero, 0(s5)
    ld      s6, 0(s4)
    mv      a0, s1                          # room for a new validator, before any change
    call    lantern_validator_room
    beqz    a0, 9f
    ADDRESS a0, lantern_type_DepositData    # leaf = hash_tree_root(deposit.data)
    ADDQ    a1, s2, Deposit_data
    mv      a2, s4
    addi    a3, sp, L
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 7f
    li      t0, DEPOSIT_CONTRACT_TREE_DEPTH + 1
    sd      t0, (L + 32)(sp)
    LDQ     t0, s1, BeaconState_eth1_deposit_index
    sd      t0, (L + 40)(sp)
    addi    a0, sp, L                       # assert is_valid_merkle_branch(...)
    addi    a1, s2, Deposit_proof
    addi    a2, sp, (L + 32)
    addi    a3, sp, (L + 40)
    ADDQ    a4, s1, BeaconState_eth1_data + Eth1Data_deposit_root
    addi    a5, sp, (L + 48)
    call    lantern_is_valid_merkle_branch
    bnez    a0, 7f
    ld      t0, (L + 48)(sp)
    li      a0, LANTERN_INVALID_DEPOSIT
    beqz    t0, 6f
    LDQ     t0, s1, BeaconState_eth1_deposit_index      # state.eth1_deposit_index += 1
    addi    t1, t0, 1
    li      a0, LANTERN_INVALID_OVERFLOW
    bltu    t1, t0, 6f
    STQ     t1, s1, BeaconState_eth1_deposit_index
    sd      s6, 0(s4)
    mv      a0, s1
    ADDQ    a1, s2, Deposit_data
    mv      a2, s3
    mv      a3, s4
    call    lantern_apply_deposit
7:  LEAVE 64
6:  sd      a0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 64
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
SPEC_END process_deposit
.endif

.if FORK >= FORK_ELECTRA
/* s1 state, s2 deposit, s3 config, s4 scratch. Locals: L valid, L+8 index. */
SPEC_FUNCTION apply_pending_deposit
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      a0, s1
    addi    a1, s2, PendingDeposit_pubkey
    call    lantern_find_pubkey
    li      t0, -1
    bne     a0, t0, 1f
    mv      a0, s2                          # a new public key: a validator when the signature is valid
    mv      a1, s3
    mv      a2, s4
    addi    a3, sp, L
    call    lantern_is_valid_deposit_signature
    bnez    a0, 7f
    ld      t0, L(sp)
    beqz    t0, 8f
    mv      a0, s1
    addi    a1, s2, PendingDeposit_pubkey
    addi    a2, s2, PendingDeposit_withdrawal_credentials
    addi    a3, s2, PendingDeposit_amount
    call    lantern_add_validator_to_registry
    j       7f
1:  sd      a0, (L + 8)(sp)                 # increase_balance(state, validator_index, deposit.amount)
    mv      a0, s1
    addi    a1, sp, (L + 8)
    addi    a2, s2, PendingDeposit_amount
    call    lantern_increase_balance
8:  li      a0, LANTERN_OK
7:  LEAVE 16
SPEC_END apply_pending_deposit
.endif

.if FORK >= FORK_ELECTRA
.set POSTPONE_BYTES, MAX_PENDING_DEPOSITS_PER_EPOCH * PendingDeposit__mem
.endif

.if FORK >= FORK_ELECTRA
/*
 * s1 state, s2 config, s3 scratch, s4 result, s5 scratch size, s6 postponed,
 * s7 available, s8 processed, s9 next deposit index, s10 postponed count.
 * Locals: L current epoch, L+8 next epoch, L+16 churn, L+24 reached, L+32 finalized slot,
 * L+40 the deposit (PendingDeposit__mem bytes), L+232 the entries kept.
 */
SPEC_FUNCTION process_pending_deposits
    ENTER 240
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH_B s3, s1, 1, POSTPONE_BYTES, 9f
    mv      a0, s1
    call    lantern_validator_room
    li      t0, MAX_PENDING_DEPOSITS_PER_EPOCH
    bltu    a0, t0, 9f
    sd      zero, 0(s4)
    ld      s5, 0(s3)
    li      t0, POSTPONE_BYTES
    sub     t0, s5, t0
    add     s6, s3, t0                      # deposits_to_postpone: at the end of scratch
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      t0, L(sp)
    addi    t0, t0, 1
    sd      t0, (L + 8)(sp)
    li      t0, POSTPONE_BYTES              # available_for_processing
    sub     t0, s5, t0
    sd      t0, 0(s3)
    mv      a0, s1
    mv      a1, s2
    mv      a2, s3
    addi    a3, sp, (L + 16)
    call    lantern_get_activation_exit_churn_limit
    bnez    a0, 7f
    LDQ     t0, s1, BeaconState_deposit_balance_to_consume
    ld      t1, (L + 16)(sp)
    add     s7, t0, t1
    bltu    s7, t0, 6f
    li      s8, 0
    li      s9, 0
    li      s10, 0
    sd      zero, (L + 24)(sp)
    ADDQ    a0, s1, BeaconState_finalized_checkpoint + Checkpoint_epoch
    addi    a1, sp, (L + 32)
    call    lantern_compute_start_slot_at_epoch
    bnez    a0, 6f                          # the finalized slot leaves the Uint64 range
1:  PART    t0, t1, s1, BeaconState_pending_deposits
    bgeu    s9, t1, 4f                      # for deposit in state.pending_deposits
    li      t2, PendingDeposit__mem
    mul     t2, s9, t2
    add     t0, t0, t2
    ld      t1, PendingDeposit_slot(t0)
.if FORK == FORK_ELECTRA
    beqz    t1, 11f                         # a deposit request (slot > GENESIS_SLOT)
    LDQ     t2, s1, BeaconState_eth1_deposit_index
    LDQ     t3, s1, BeaconState_deposit_requests_start_index
    bltu    t2, t3, 4f                      # while Eth1 bridge deposits are pending
11:
.endif
    ld      t2, (L + 32)(sp)
    bgtu    t1, t2, 4f                      # a deposit not yet finalized
    li      t1, MAX_PENDING_DEPOSITS_PER_EPOCH
    bgeu    s9, t1, 4f
    addi    a0, sp, (L + 40)                # a copy of the deposit, apart from the state
    mv      a1, t0
    li      a2, PendingDeposit__mem
    call    lantern_copy
    mv      a0, s1
    addi    a1, sp, (L + 40 + PendingDeposit_pubkey)
    call    lantern_find_pubkey
    li      t0, -1
    beq     a0, t0, 3f                      # not exited, not withdrawn
    PART    t0, t1, s1, BeaconState_validators
    slli    t1, a0, 7
    add     t0, t0, t1
    ld      t1, Validator_withdrawable_epoch(t0)
    ld      t2, (L + 8)(sp)
    bltu    t1, t2, 2f                      # withdrawn: apply
    ld      t1, Validator_exit_epoch(t0)
    li      t2, -1
    beq     t1, t2, 3f
    li      t0, PendingDeposit__mem         # exited: postpone
    mul     a0, s10, t0
    add     a0, s6, a0
    addi    a1, sp, (L + 40)
    li      a2, PendingDeposit__mem
    call    lantern_copy
    addi    s10, s10, 1
    j       25f
3:  ld      t0, (L + 40 + PendingDeposit_amount)(sp)
    add     t0, s8, t0                      # is_churn_limit_reached = processed_amount + deposit.amount > available
    bltu    t0, s8, 6f
    bgtu    t0, s7, 35f
    mv      s8, t0
2:  li      t0, POSTPONE_BYTES
    sub     t0, s5, t0
    sd      t0, 0(s3)
    mv      a0, s1
    addi    a1, sp, (L + 40)
    mv      a2, s2
    mv      a3, s3
    call    lantern_apply_pending_deposit
    bnez    a0, 7f
25: addi    s9, s9, 1
    j       1b
35: li      t0, 1
    sd      t0, (L + 24)(sp)
4:  PART    a0, t1, s1, BeaconState_pending_deposits    # pending_deposits[next_deposit_index:] + deposits_to_postpone
    sub     t0, t1, s9
    sd      t0, (L + 232)(sp)               # the entries kept
    li      t2, PendingDeposit__mem
    mul     a2, t0, t2
    mul     a1, s9, t2
    add     a1, a0, a1
    call    lantern_copy
    PART    a0, t1, s1, BeaconState_pending_deposits
    ld      t0, (L + 232)(sp)
    li      t2, PendingDeposit__mem
    mul     t0, t0, t2
    add     a0, a0, t0
    mv      a1, s6
    mul     a2, s10, t2
    call    lantern_copy
    ld      t0, (L + 232)(sp)
    add     t0, t0, s10
    STQ     t0, s1, BeaconState_pending_deposits + 8
    ld      t0, (L + 24)(sp)                # deposit_balance_to_consume
    li      t1, 0
    beqz    t0, 45f
    sub     t1, s7, s8                      # available_for_processing - processed_amount
45: STQ     t1, s1, BeaconState_deposit_balance_to_consume
    j       8f
6:  li      t0, LANTERN_INVALID_OVERFLOW
    sd      t0, 0(s4)
8:  li      a0, LANTERN_OK
7:  LEAVE 240
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 240
SPEC_END process_pending_deposits
.endif
