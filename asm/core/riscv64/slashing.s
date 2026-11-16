/*
 * Slashings, RISC-V. Requirements: docs/reference/block-processing.md.
 */

/*
 * s1 state, s2 slashed index, s3 whistleblower pointer, s4 config, s5 scratch, s6 result,
 * s7 validator. Locals: L epoch, L+8 penalty, L+16 proposer, L+24 whistleblower reward,
 * L+32 proposer reward, L+40 whistleblower, L+48 slashed index.
 */
FUNCTION lantern_slash_validator
    ENTER 64
    mv      s1, a0
    ld      s2, 0(a1)
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    NEED_SCRATCH s5, s1, 1, 9f
    sd      zero, 0(s6)
    sd      s2, (L + 48)(sp)
    LDQ     t0, s1, BeaconState_validators + 8
    bgeu    s2, t0, 4f
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    mv      a0, s1                          # initiate_validator_exit(state, slashed_index)
    addi    a1, sp, (L + 48)
    mv      a2, s4
    mv      a3, s5
    mv      a4, s6
    call    lantern_initiate_validator_exit
    bnez    a0, 7f
    ld      t0, 0(s6)
    bnez    t0, 8f
    PART    s7, t0, s1, BeaconState_validators
    slli    t0, s2, 7
    add     s7, s7, t0
    li      t0, 1
    sb      t0, Validator_slashed(s7)
    ld      t0, L(sp)                       # withdrawable_epoch = max(withdrawable_epoch, epoch + EPOCHS_PER_SLASHINGS_VECTOR)
    li      t1, EPOCHS_PER_SLASHINGS_VECTOR
    add     t1, t0, t1
    bltu    t1, t0, 5f
    ld      t2, Validator_withdrawable_epoch(s7)
    bgtu    t2, t1, 1f
    mv      t2, t1
1:  sd      t2, Validator_withdrawable_epoch(s7)
    li      t1, (EPOCHS_PER_SLASHINGS_VECTOR - 1)   # slashings[epoch % EPOCHS_PER_SLASHINGS_VECTOR] += effective_balance
    and     t0, t0, t1
    ADDQ    t1, s1, BeaconState_slashings
    slli    t0, t0, 3
    add     t1, t1, t0
    ld      t2, 0(t1)
    ld      t3, Validator_effective_balance(s7)
    add     t2, t2, t3
    bltu    t2, t3, 5f
    sd      t2, 0(t1)
    li      t4, MIN_SLASHING_PENALTY_QUOTIENT_ELECTRA
    divu    t4, t3, t4
    sd      t4, (L + 8)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 48)
    addi    a2, sp, (L + 8)
    call    lantern_decrease_balance
    mv      a0, s1
    addi    a1, sp, (L + 16)
    call    lantern_get_beacon_proposer_index
    ld      t0, (L + 16)(sp)                # whistleblower_index = proposer_index when None
    beqz    s3, 2f
    ld      t0, 0(s3)
2:  sd      t0, (L + 40)(sp)
    ld      t3, Validator_effective_balance(s7)
    li      t4, WHISTLEBLOWER_REWARD_QUOTIENT_ELECTRA
    divu    t4, t3, t4                      # whistleblower_reward
    li      t5, PROPOSER_WEIGHT
    mul     t5, t4, t5
    srli    t5, t5, 6                       # // WEIGHT_DENOMINATOR
    sd      t5, (L + 32)(sp)
    sub     t4, t4, t5
    sd      t4, (L + 24)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 16)
    addi    a2, sp, (L + 32)
    call    lantern_increase_balance
    mv      a0, s1
    addi    a1, sp, (L + 40)
    addi    a2, sp, (L + 24)
    call    lantern_increase_balance
8:  li      a0, LANTERN_OK
7:  LEAVE 64
4:  li      t0, LANTERN_INVALID_VALIDATOR_INDEX
    sd      t0, 0(s6)
    li      a0, LANTERN_OK
    LEAVE 64
5:  li      t0, LANTERN_INVALID_OVERFLOW
    sd      t0, 0(s6)
    li      a0, LANTERN_OK
    LEAVE 64
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
END_FUNCTION lantern_slash_validator

.if WEIGHT_DENOMINATOR != 64
.error "lantern_slash_validator divides by WEIGHT_DENOMINATOR with a shift by 6"
.endif

LEAF lantern_is_slashable_attestation_data
    li      a3, 0                           # data_1 != data_2
    li      a4, 0
    li      t2, AttestationData__mem
1:  add     a5, a0, a4
    ld      a5, 0(a5)
    add     a6, a1, a4
    ld      a6, 0(a6)
    bne     a5, a6, 2f
    addi    a4, a4, 8
    bltu    a4, t2, 1b
    j       3f                              # equal: no double vote
2:  ld      a5, (AttestationData_target + Checkpoint_epoch)(a0)
    ld      a6, (AttestationData_target + Checkpoint_epoch)(a1)
    bne     a5, a6, 3f                      # and data_1.target.epoch == data_2.target.epoch
    li      a3, 1
    j       4f
3:  ld      a5, (AttestationData_source + Checkpoint_epoch)(a0)     # surround vote
    ld      a6, (AttestationData_source + Checkpoint_epoch)(a1)
    bgeu    a5, a6, 4f
    ld      a5, (AttestationData_target + Checkpoint_epoch)(a1)
    ld      a6, (AttestationData_target + Checkpoint_epoch)(a0)
    sltu    a3, a5, a6
4:  sd      a3, 0(a2)
    RETURN_OK
END_FUNCTION lantern_is_slashable_attestation_data

.if (AttestationData__mem & 7) || (AttestationData__mem != 128)
.error "lantern_is_slashable_attestation_data compares AttestationData 8 bytes at a time"
.endif

/*
 * s1 state, s2 proposer slashing, s3 config, s4 scratch, s5 result, s6 proposer,
 * s7 signed header. Locals: L predicate, L+8 epoch, L+16 domain type, L+24 domain (32),
 * L+56 signing root as a ByteList (56), L+112 index.
 */
FUNCTION lantern_process_proposer_slashing
    ENTER 128
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    NEED_SCRATCH s4, s1, 1, 9f
    sd      zero, 0(s5)
    li      a0, LANTERN_INVALID_PROPOSER_SLASHING
    addi    t0, s2, (ProposerSlashing_signed_header_1 + SignedBeaconBlockHeader_message)
    addi    t1, s2, (ProposerSlashing_signed_header_2 + SignedBeaconBlockHeader_message)
    ld      t2, BeaconBlockHeader_slot(t0)
    ld      t3, BeaconBlockHeader_slot(t1)
    bne     t2, t3, 6f                      # assert header_1.slot == header_2.slot
    ld      t2, BeaconBlockHeader_proposer_index(t0)
    ld      t3, BeaconBlockHeader_proposer_index(t1)
    bne     t2, t3, 6f                      # assert header_1.proposer_index == header_2.proposer_index
    li      t4, 0                           # assert header_1 != header_2
    li      t5, BeaconBlockHeader__mem
1:  add     t3, t0, t4
    ld      t3, 0(t3)
    add     t6, t1, t4
    ld      t6, 0(t6)
    bne     t3, t6, 2f
    addi    t4, t4, 8
    bltu    t4, t5, 1b
    j       6f
2:  LDQ     t3, s1, BeaconState_validators + 8
    li      a0, LANTERN_INVALID_VALIDATOR_INDEX
    bgeu    t2, t3, 6f
    sd      t2, (L + 112)(sp)
    PART    s6, t3, s1, BeaconState_validators
    slli    t2, t2, 7
    add     s6, s6, t2
    mv      a0, s1
    addi    a1, sp, (L + 8)
    call    lantern_get_current_epoch
    mv      a0, s6                          # assert is_slashable_validator(proposer, current epoch)
    addi    a1, sp, (L + 8)
    addi    a2, sp, L
    call    lantern_is_slashable_validator
    ld      t0, L(sp)
    li      a0, LANTERN_INVALID_PROPOSER_SLASHING
    beqz    t0, 6f
    addi    s7, s2, ProposerSlashing_signed_header_1
    addi    a0, sp, L
    call    check_header_signature
    bnez    a0, 3f
    addi    s7, s2, ProposerSlashing_signed_header_2
    addi    a0, sp, L
    call    check_header_signature
3:  CHECK_STATUS s5, 7f, 8f
    mv      a0, s1                          # slash_validator(state, header_1.proposer_index)
    addi    a1, sp, (L + 112)
    li      a2, 0
    mv      a3, s3
    mv      a4, s4
    mv      a5, s5
    call    lantern_slash_validator
    j       7f
8:  li      a0, LANTERN_OK
7:  LEAVE 128
6:  sd      a0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 128
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 128
END_FUNCTION lantern_process_proposer_slashing

/*
 * L0 of lantern_process_proposer_slashing: check the signature of signed header s7 by
 * proposer s6, with state s1 and scratch s4. a0 points at the caller's locals: +8 epoch,
 * +16 domain type, +24 domain, +56 signing root as a ByteList. Returns a0: 0, a status,
 * or LANTERN_INVALID_PROPOSER_SLASHING. Locals: sp+0 the caller's locals.
 */
LOCAL_FUNCTION check_header_signature
    FRAME 16
    sd      a0, 0(sp)
    mv      t0, a0
    ld      t1, (SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(s7)
    srli    t1, t1, LOG2_SLOTS_PER_EPOCH
    sd      t1, 8(t0)                       # compute_epoch_at_slot(signed_header.message.slot)
    li      t1, DOMAIN_BEACON_PROPOSER
    sw      t1, 16(t0)
    mv      a0, s1
    addi    a1, t0, 16
    addi    a2, t0, 8
    mv      a3, s4
    addi    a4, t0, 24
    call    lantern_get_domain
    bnez    a0, 1f
    ld      t0, 0(sp)
    ADDRESS a0, lantern_type_BeaconBlockHeader
    addi    a1, s7, SignedBeaconBlockHeader_message
    addi    a2, t0, 24
    mv      a3, s4
    addi    a4, t0, 80
    call    lantern_compute_signing_root
    bnez    a0, 1f
    ld      t0, 0(sp)
    addi    a0, s6, Validator_pubkey
    addi    a1, s7, SignedBeaconBlockHeader_signature
    addi    a2, t0, 56
    mv      a3, s4
    call    verify_root_signature
    bnez    a0, 1f
    bnez    a1, 1f
    li      a0, LANTERN_INVALID_PROPOSER_SLASHING
1:  UNFRAME 16
END_FUNCTION check_header_signature

/*
 * s1 state, s2 attester slashing, s3 config, s4 scratch, s5 result, s6 attestation_1,
 * s7 attestation_2, s8 cursor 1, s9 cursor 2, s10 slashed_any.
 * Locals: L predicate, L+8 epoch, L+16 index, L+24 end 1, L+32 end 2, L+40 scratch size.
 */
FUNCTION lantern_process_attester_slashing
    ENTER 48
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    NEED_SCRATCH s4, s1, 8, 9f
    sd      zero, 0(s5)
    ld      t0, 0(s4)
    sd      t0, (L + 40)(sp)
    PART    s6, t0, s2, AttesterSlashing_attestation_1
    PART    s7, t0, s2, AttesterSlashing_attestation_2
    addi    a0, s6, IndexedAttestation_data # assert is_slashable_attestation_data(data_1, data_2)
    addi    a1, s7, IndexedAttestation_data
    addi    a2, sp, L
    call    lantern_is_slashable_attestation_data
    ld      t0, L(sp)
    li      a0, LANTERN_INVALID_ATTESTER_SLASHING
    beqz    t0, 6f
    mv      a0, s1                          # assert is_valid_indexed_attestation(state, attestation_1)
    mv      a1, s6
    mv      a2, s4
    addi    a3, sp, L
    call    lantern_is_valid_indexed_attestation
    CHECK_STATUS s5, 7f, 8f
    ld      t0, L(sp)
    li      a0, LANTERN_INVALID_ATTESTER_SLASHING
    beqz    t0, 6f
    ld      t0, (L + 40)(sp)
    sd      t0, 0(s4)
    mv      a0, s1
    mv      a1, s7
    mv      a2, s4
    addi    a3, sp, L
    call    lantern_is_valid_indexed_attestation
    CHECK_STATUS s5, 7f, 8f
    ld      t0, L(sp)
    li      a0, LANTERN_INVALID_ATTESTER_SLASHING
    beqz    t0, 6f
    mv      a0, s1
    addi    a1, sp, (L + 8)
    call    lantern_get_current_epoch
    li      s10, 0
    PART    s8, t0, s6, IndexedAttestation_attesting_indices   # the sorted intersection, by merge
    slli    t0, t0, 3
    add     t0, s8, t0
    sd      t0, (L + 24)(sp)
    PART    s9, t0, s7, IndexedAttestation_attesting_indices
    slli    t0, t0, 3
    add     t0, s9, t0
    sd      t0, (L + 32)(sp)
1:  ld      t0, (L + 24)(sp)
    bgeu    s8, t0, 4f
    ld      t0, (L + 32)(sp)
    bgeu    s9, t0, 4f
    ld      t1, 0(s8)
    ld      t2, 0(s9)
    bltu    t1, t2, 2f
    bgtu    t1, t2, 3f
    addi    s8, s8, 8
    addi    s9, s9, 8
    sd      t1, (L + 16)(sp)
    PART    a0, t0, s1, BeaconState_validators     # if is_slashable_validator(state.validators[index], epoch)
    slli    t1, t1, 7
    add     a0, a0, t1
    addi    a1, sp, (L + 8)
    addi    a2, sp, L
    call    lantern_is_slashable_validator
    ld      t0, L(sp)
    beqz    t0, 1b
    ld      t0, (L + 40)(sp)
    sd      t0, 0(s4)
    mv      a0, s1
    addi    a1, sp, (L + 16)
    li      a2, 0
    mv      a3, s3
    mv      a4, s4
    mv      a5, s5
    call    lantern_slash_validator
    bnez    a0, 7f
    ld      t0, 0(s5)
    bnez    t0, 8f
    li      s10, 1
    j       1b
2:  addi    s8, s8, 8
    j       1b
3:  addi    s9, s9, 8
    j       1b
4:  li      a0, LANTERN_INVALID_ATTESTER_SLASHING   # assert slashed_any
    beqz    s10, 6f
8:  li      a0, LANTERN_OK
7:  LEAVE 48
6:  sd      a0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 48
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
END_FUNCTION lantern_process_attester_slashing
