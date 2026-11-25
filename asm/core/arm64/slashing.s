/*
 * Slashings, ARM64. Requirements: docs/reference/block-processing.md.
 */

/*
 * x19 state, x20 slashed index, x21 whistleblower pointer, x22 config, x23 scratch, x24 result,
 * x25 validator. Locals: L epoch, L+8 penalty, L+16 proposer, L+24 whistleblower reward,
 * L+32 proposer reward, L+40 whistleblower, L+48 slashed index.
 */
SPEC_FUNCTION slash_validator
    ENTER 64
    mov     x19, x0
    ldr     x20, [x1]
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
.if FORK >= FORK_FULU
    NEED_SCRATCH x23, x19, 1, 9f
.else
    NEED_SCRATCH x23, x19, 2, 9f                /* get_beacon_proposer_index takes S(2) */
.endif
    str     xzr, [x24]
    str     x20, [sp, #(L + 48)]
    LDQ     x9, x19, BeaconState_validators + 8
    cmp     x20, x9
    b.hs    4f
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    mov     x0, x19                         /* initiate_validator_exit(state, slashed_index) */
    add     x1, sp, #(L + 48)
    mov     x2, x22
    mov     x3, x23
    mov     x4, x24
    bl      lantern_initiate_validator_exit
    cbnz    x0, 7f
    ldr     x9, [x24]
    cbnz    x9, 8f
    PART    x25, x9, x19, BeaconState_validators
    add     x25, x25, x20, lsl #7
    mov     w9, #1
    strb    w9, [x25, #Validator_slashed]
    ldr     x9, [sp, #L]                    /* withdrawable_epoch = max(withdrawable_epoch, epoch + EPOCHS_PER_SLASHINGS_VECTOR) */
    MOVQ    x10, EPOCHS_PER_SLASHINGS_VECTOR
    adds    x10, x9, x10
    b.cs    5f
    ldr     x11, [x25, #Validator_withdrawable_epoch]
    cmp     x11, x10
    csel    x11, x11, x10, hi
    str     x11, [x25, #Validator_withdrawable_epoch]
    and     x9, x9, #(EPOCHS_PER_SLASHINGS_VECTOR - 1)  /* slashings[epoch % EPOCHS_PER_SLASHINGS_VECTOR] += effective_balance */
    ADDQ    x10, x19, BeaconState_slashings
    add     x10, x10, x9, lsl #3
    ldr     x11, [x10]
    ldr     x12, [x25, #Validator_effective_balance]
    adds    x11, x11, x12
    b.cs    5f
    str     x11, [x10]
    MOVQ    x13, FORK_MIN_SLASHING_PENALTY_QUOTIENT
    udiv    x13, x12, x13
    str     x13, [sp, #(L + 8)]
    mov     x0, x19
    add     x1, sp, #(L + 48)
    add     x2, sp, #(L + 8)
    bl      lantern_decrease_balance
    mov     x0, x19
.if FORK >= FORK_FULU
    add     x1, sp, #(L + 16)
    bl      lantern_get_beacon_proposer_index
.else
    mov     x1, x23
    add     x2, sp, #(L + 16)
    bl      lantern_get_beacon_proposer_index
    cbz     x0, 2f
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    7f
    str     x0, [x24]
    b       8f
2:
.endif
    ldr     x9, [sp, #(L + 16)]             /* whistleblower_index = proposer_index when None */
    cbz     x21, 1f
    ldr     x9, [x21]
1:  str     x9, [sp, #(L + 40)]
    ldr     x12, [x25, #Validator_effective_balance]
    MOVQ    x13, FORK_WHISTLEBLOWER_REWARD_QUOTIENT
    udiv    x13, x12, x13                   /* whistleblower_reward */
.if FORK >= FORK_ALTAIR
    mov     x14, #PROPOSER_WEIGHT
    mul     x14, x13, x14
    lsr     x14, x14, #6                    /* // WEIGHT_DENOMINATOR */
.else
    mov     x14, #PROPOSER_REWARD_QUOTIENT
    udiv    x14, x13, x14                   /* proposer_reward = whistleblower_reward // PROPOSER_REWARD_QUOTIENT */
.endif
    str     x14, [sp, #(L + 32)]
    sub     x13, x13, x14
    str     x13, [sp, #(L + 24)]
    mov     x0, x19
    add     x1, sp, #(L + 16)
    add     x2, sp, #(L + 32)
    bl      lantern_increase_balance
    mov     x0, x19
    add     x1, sp, #(L + 40)
    add     x2, sp, #(L + 24)
    bl      lantern_increase_balance
8:  mov     x0, #LANTERN_OK
7:  LEAVE 64
4:  mov     x9, #LANTERN_INVALID_VALIDATOR_INDEX
    str     x9, [x24]
    mov     x0, #LANTERN_OK
    LEAVE 64
5:  mov     x9, #LANTERN_INVALID_OVERFLOW
    str     x9, [x24]
    mov     x0, #LANTERN_OK
    LEAVE 64
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
SPEC_END slash_validator

SPEC_LEAF is_slashable_attestation_data
    mov     x3, #0                          /* data_1 != data_2 */
    mov     x4, #0
1:  ldr     x5, [x0, x4]
    ldr     x6, [x1, x4]
    cmp     x5, x6
    b.ne    2f
    add     x4, x4, #8
    cmp     x4, #AttestationData__mem
    b.lo    1b
    b       3f                              /* equal: no double vote */
2:  ldr     x5, [x0, #(AttestationData_target + Checkpoint_epoch)]
    ldr     x6, [x1, #(AttestationData_target + Checkpoint_epoch)]
    cmp     x5, x6                          /* and data_1.target.epoch == data_2.target.epoch */
    b.ne    3f
    mov     x3, #1
    b       4f
3:  ldr     x5, [x0, #(AttestationData_source + Checkpoint_epoch)]  /* surround vote */
    ldr     x6, [x1, #(AttestationData_source + Checkpoint_epoch)]
    cmp     x5, x6
    b.hs    4f
    ldr     x5, [x1, #(AttestationData_target + Checkpoint_epoch)]
    ldr     x6, [x0, #(AttestationData_target + Checkpoint_epoch)]
    cmp     x5, x6
    cset    x3, lo
4:  str     x3, [x2]
    RETURN_OK
SPEC_END is_slashable_attestation_data

.if (AttestationData__mem & 7) || (AttestationData__mem != 128)
.error "lantern_is_slashable_attestation_data compares AttestationData 8 bytes at a time"
.endif

/*
 * x19 state, x20 proposer slashing, x21 config, x22 scratch, x23 result, x24 proposer,
 * x25 signed header. Locals: L predicate, L+8 epoch, L+16 domain type, L+24 domain (32),
 * L+56 signing root as a ByteList (56), L+112 index.
 */
SPEC_FUNCTION process_proposer_slashing
    ENTER 128
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
.if FORK >= FORK_FULU
    NEED_SCRATCH x22, x19, 1, 9f
.else
    NEED_SCRATCH x22, x19, 2, 9f                /* slash_validator takes S(2) */
.endif
    str     xzr, [x23]
    mov     x0, #LANTERN_INVALID_PROPOSER_SLASHING
    add     x9, x20, #(ProposerSlashing_signed_header_1 + SignedBeaconBlockHeader_message)
    add     x10, x20, #(ProposerSlashing_signed_header_2 + SignedBeaconBlockHeader_message)
    ldr     x11, [x9, #BeaconBlockHeader_slot]
    ldr     x12, [x10, #BeaconBlockHeader_slot]
    cmp     x11, x12                        /* assert header_1.slot == header_2.slot */
    b.ne    6f
    ldr     x11, [x9, #BeaconBlockHeader_proposer_index]
    ldr     x12, [x10, #BeaconBlockHeader_proposer_index]
    cmp     x11, x12                        /* assert header_1.proposer_index == header_2.proposer_index */
    b.ne    6f
    mov     x13, #0                         /* assert header_1 != header_2 */
1:  ldr     x14, [x9, x13]
    ldr     x15, [x10, x13]
    cmp     x14, x15
    b.ne    2f
    add     x13, x13, #8
    cmp     x13, #BeaconBlockHeader__mem
    b.lo    1b
    b       6f
2:  LDQ     x12, x19, BeaconState_validators + 8
    cmp     x11, x12
    mov     x0, #LANTERN_INVALID_VALIDATOR_INDEX
    b.hs    6f
    str     x11, [sp, #(L + 112)]
    PART    x24, x12, x19, BeaconState_validators
    add     x24, x24, x11, lsl #7
    mov     x0, x19
    add     x1, sp, #(L + 8)
    bl      lantern_get_current_epoch
    mov     x0, x24                         /* assert is_slashable_validator(proposer, current epoch) */
    add     x1, sp, #(L + 8)
    add     x2, sp, #L
    bl      lantern_is_slashable_validator
    ldr     x9, [sp, #L]
    mov     x0, #LANTERN_INVALID_PROPOSER_SLASHING
    cbz     x9, 6f
    add     x25, x20, #ProposerSlashing_signed_header_1
    add     x0, sp, #L
    bl      lantern_check_header_signature
    cbnz    x0, 3f
    add     x25, x20, #ProposerSlashing_signed_header_2
    add     x0, sp, #L
    bl      lantern_check_header_signature
3:  CHECK_STATUS x23, 7f, 8f
    mov     x0, x19                         /* slash_validator(state, header_1.proposer_index) */
    add     x1, sp, #(L + 112)
    mov     x2, #0
    mov     x3, x21
    mov     x4, x22
    mov     x5, x23
    bl      lantern_slash_validator
    b       7f
8:  mov     x0, #LANTERN_OK
7:  LEAVE 128
6:  str     x0, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 128
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 128
SPEC_END process_proposer_slashing

/*
 * A helper of lantern_process_proposer_slashing: check the signature of signed header x25 by
 * proposer x24, with state x19 and scratch x22. x0 points at the caller's locals: +8 epoch,
 * +16 domain type, +24 domain, +56 signing root as a ByteList. Returns x0: 0, a status,
 * or LANTERN_INVALID_PROPOSER_SLASHING.
 */
LOCAL_FUNCTION lantern_check_header_signature
    FRAME 16
    str     x0, [sp, #16]
    mov     x9, x0
    ldr     x10, [x25, #(SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)]
    lsr     x10, x10, #LOG2_SLOTS_PER_EPOCH
    str     x10, [x9, #8]                   /* compute_epoch_at_slot(signed_header.message.slot) */
    mov     w10, #DOMAIN_BEACON_PROPOSER
    str     w10, [x9, #16]
    mov     x0, x19
    add     x1, x9, #16
    add     x2, x9, #8
    mov     x3, x22
    add     x4, x9, #24
    bl      lantern_get_domain
    cbnz    x0, 1f
    ldr     x9, [sp, #16]
    ADDRESS x0, lantern_type_BeaconBlockHeader
    add     x1, x25, #SignedBeaconBlockHeader_message
    add     x2, x9, #24
    mov     x3, x22
    add     x4, x9, #80
    bl      lantern_compute_signing_root
    cbnz    x0, 1f
    ldr     x9, [sp, #16]
    add     x0, x24, #Validator_pubkey
    add     x1, x25, #SignedBeaconBlockHeader_signature
    add     x2, x9, #56
    mov     x3, x22
    bl      lantern_verify_root_signature
    cbnz    x0, 1f
    mov     x0, #LANTERN_INVALID_PROPOSER_SLASHING
    cmp     x1, #0
    csel    x0, x0, xzr, eq
1:  UNFRAME 16
END_FUNCTION lantern_check_header_signature

/*
 * x19 state, x20 attester slashing, x21 config, x22 scratch, x23 result, x24 attestation_1,
 * x25 attestation_2, x26 cursor 1, x27 cursor 2, x28 slashed_any.
 * Locals: L predicate, L+8 epoch, L+16 index, L+24 end 1, L+32 end 2, L+40 scratch size.
 */
SPEC_FUNCTION process_attester_slashing
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    NEED_SCRATCH x22, x19, 8, 9f
    str     xzr, [x23]
    ldr     x9, [x22]
    str     x9, [sp, #(L + 40)]
    PART    x24, x9, x20, AttesterSlashing_attestation_1
    PART    x25, x9, x20, AttesterSlashing_attestation_2
    add     x0, x24, #IndexedAttestation_data   /* assert is_slashable_attestation_data(data_1, data_2) */
    add     x1, x25, #IndexedAttestation_data
    add     x2, sp, #L
    bl      lantern_is_slashable_attestation_data
    ldr     x9, [sp, #L]
    mov     x0, #LANTERN_INVALID_ATTESTER_SLASHING
    cbz     x9, 6f
    mov     x0, x19                         /* assert is_valid_indexed_attestation(state, attestation_1) */
    mov     x1, x24
    mov     x3, x22
    add     x4, sp, #L
    ldr     x2, [x21, #CONFIG_PUBKEY_CACHE]
    bl      lantern_is_valid_indexed_attestation
    CHECK_STATUS x23, 7f, 8f
    ldr     x9, [sp, #L]
    mov     x0, #LANTERN_INVALID_ATTESTER_SLASHING
    cbz     x9, 6f
    ldr     x9, [sp, #(L + 40)]
    str     x9, [x22]
    mov     x0, x19
    mov     x1, x25
    mov     x3, x22
    add     x4, sp, #L
    ldr     x2, [x21, #CONFIG_PUBKEY_CACHE]
    bl      lantern_is_valid_indexed_attestation
    CHECK_STATUS x23, 7f, 8f
    ldr     x9, [sp, #L]
    mov     x0, #LANTERN_INVALID_ATTESTER_SLASHING
    cbz     x9, 6f
    mov     x0, x19
    add     x1, sp, #(L + 8)
    bl      lantern_get_current_epoch
    mov     x28, #0
    PART    x26, x9, x24, IndexedAttestation_attesting_indices   /* the sorted intersection, by merge */
    add     x9, x26, x9, lsl #3
    str     x9, [sp, #(L + 24)]
    PART    x27, x9, x25, IndexedAttestation_attesting_indices
    add     x9, x27, x9, lsl #3
    str     x9, [sp, #(L + 32)]
1:  ldr     x9, [sp, #(L + 24)]
    cmp     x26, x9
    b.hs    4f
    ldr     x9, [sp, #(L + 32)]
    cmp     x27, x9
    b.hs    4f
    ldr     x10, [x26]
    ldr     x11, [x27]
    cmp     x10, x11
    b.lo    2f
    b.hi    3f
    add     x26, x26, #8
    add     x27, x27, #8
    str     x10, [sp, #(L + 16)]
    PART    x0, x9, x19, BeaconState_validators     /* if is_slashable_validator(state.validators[index], epoch) */
    add     x0, x0, x10, lsl #7
    add     x1, sp, #(L + 8)
    add     x2, sp, #L
    bl      lantern_is_slashable_validator
    ldr     x9, [sp, #L]
    cbz     x9, 1b
    ldr     x9, [sp, #(L + 40)]
    str     x9, [x22]
    mov     x0, x19
    add     x1, sp, #(L + 16)
    mov     x2, #0
    mov     x3, x21
    mov     x4, x22
    mov     x5, x23
    bl      lantern_slash_validator
    cbnz    x0, 7f
    ldr     x9, [x23]
    cbnz    x9, 8f
    mov     x28, #1
    b       1b
2:  add     x26, x26, #8
    b       1b
3:  add     x27, x27, #8
    b       1b
4:  mov     x0, #LANTERN_INVALID_ATTESTER_SLASHING  /* assert slashed_any */
    cbz     x28, 6f
8:  mov     x0, #LANTERN_OK
7:  LEAVE 48
6:  str     x0, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END process_attester_slashing
