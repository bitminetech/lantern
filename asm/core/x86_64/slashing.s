/*
 * Slashings, x86-64. Requirements: docs/reference/block-processing.md.
 */

/*
 * rbx state, rbp slashed index, r12 whistleblower pointer, r13 config, r14 scratch, r15 result,
 * S7 validator. Locals: L epoch, L+8 penalty, L+16 proposer, L+24 whistleblower reward,
 * L+32 proposer reward, L+40 whistleblower, L+48 slashed index.
 */
SPEC_FUNCTION slash_validator
    ENTER 64
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r9, %r15
.if FORK >= FORK_FULU
    NEED_SCRATCH %r14, %rbx, 1, 9f
.else
    NEED_SCRATCH %r14, %rbx, 2, 9f              # get_beacon_proposer_index takes S(2)
.endif
    movq    $0, (%r15)
    mov     %rbp, (L + 48)(%rsp)
    cmp     (BeaconState_validators + 8)(%rbx), %rbp
    jae     4f
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     %rbx, %rdi                      # initiate_validator_exit(state, slashed_index)
    lea     (L + 48)(%rsp), %rsi
    mov     %r13, %rdx
    mov     %r14, %rcx
    mov     %r15, %r8
    call    lantern_initiate_validator_exit
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (%r15)
    jne     8f
    VALIDATOR %rcx, %rbx, %rbp
    mov     %rcx, S7(%rsp)
    movb    $1, Validator_slashed(%rcx)
    mov     L(%rsp), %rax                   # withdrawable_epoch = max(withdrawable_epoch, epoch + EPOCHS_PER_SLASHINGS_VECTOR)
    mov     %rax, %rdx
    add     $EPOCHS_PER_SLASHINGS_VECTOR, %rdx
    jc      5f
    cmp     Validator_withdrawable_epoch(%rcx), %rdx
    jbe     1f
    mov     %rdx, Validator_withdrawable_epoch(%rcx)
1:  and     $(EPOCHS_PER_SLASHINGS_VECTOR - 1), %eax    # slashings[epoch % EPOCHS_PER_SLASHINGS_VECTOR] += effective_balance
    lea     BeaconState_slashings(%rbx,%rax,8), %rdx
    mov     Validator_effective_balance(%rcx), %rax
    mov     (%rdx), %r8
    add     %rax, %r8
    jc      5f
    mov     %r8, (%rdx)
    MOVQ    %rcx, FORK_MIN_SLASHING_PENALTY_QUOTIENT
    xor     %edx, %edx
    div     %rcx
    mov     %rax, (L + 8)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 48)(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_decrease_balance
    mov     %rbx, %rdi
.if FORK >= FORK_FULU
    lea     (L + 16)(%rsp), %rsi
    call    lantern_get_beacon_proposer_index
.else
    mov     %r14, %rsi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_get_beacon_proposer_index
    test    %rax, %rax
    jz      3f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      7f
    mov     %rax, (%r15)
    jmp     8f
3:
.endif
    mov     (L + 16)(%rsp), %rax            # whistleblower_index = proposer_index when None
    test    %r12, %r12
    jz      2f
    mov     (%r12), %rax
2:  mov     %rax, (L + 40)(%rsp)
    mov     S7(%rsp), %rcx
    mov     Validator_effective_balance(%rcx), %rax
    MOVQ    %rcx, FORK_WHISTLEBLOWER_REWARD_QUOTIENT
    xor     %edx, %edx
    div     %rcx                            # whistleblower_reward
.if FORK >= FORK_ALTAIR
    imul    $PROPOSER_WEIGHT, %rax, %rcx
    shr     $6, %rcx                        # // WEIGHT_DENOMINATOR
.else
    mov     %rax, %rcx                      # proposer_reward = whistleblower_reward // PROPOSER_REWARD_QUOTIENT
    shr     $3, %rcx
.if PROPOSER_REWARD_QUOTIENT != 8
.error "slash_validator divides by PROPOSER_REWARD_QUOTIENT with a shift by 3"
.endif
.endif
    mov     %rcx, (L + 32)(%rsp)
    sub     %rcx, %rax
    mov     %rax, (L + 24)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    lea     (L + 32)(%rsp), %rdx
    call    lantern_increase_balance
    mov     %rbx, %rdi
    lea     (L + 40)(%rsp), %rsi
    lea     (L + 24)(%rsp), %rdx
    call    lantern_increase_balance
8:  xor     %eax, %eax
7:  LEAVE 64
4:  movq    $LANTERN_INVALID_VALIDATOR_INDEX, (%r15)
    xor     %eax, %eax
    LEAVE 64
5:  movq    $LANTERN_INVALID_OVERFLOW, (%r15)
    xor     %eax, %eax
    LEAVE 64
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 64
SPEC_END slash_validator

.if WEIGHT_DENOMINATOR != 64
.error "lantern_slash_validator divides by WEIGHT_DENOMINATOR with a shift by 6"
.endif

SPEC_LEAF is_slashable_attestation_data
    xor     %eax, %eax                      # data_1 != data_2
    xor     %ecx, %ecx
1:  mov     (%rdi,%rcx), %r8
    cmp     (%rsi,%rcx), %r8
    jne     2f
    add     $8, %rcx
    cmp     $AttestationData__mem, %rcx
    jb      1b
    jmp     3f                              # equal: no double vote
2:  mov     (AttestationData_target + Checkpoint_epoch)(%rdi), %r8
    cmp     (AttestationData_target + Checkpoint_epoch)(%rsi), %r8 # and data_1.target.epoch == data_2.target.epoch
    jne     3f
    mov     $1, %eax
    jmp     4f
3:  mov     (AttestationData_source + Checkpoint_epoch)(%rdi), %r8 # surround vote
    cmp     (AttestationData_source + Checkpoint_epoch)(%rsi), %r8
    jae     4f
    mov     (AttestationData_target + Checkpoint_epoch)(%rsi), %r8
    cmp     (AttestationData_target + Checkpoint_epoch)(%rdi), %r8
    setb    %al
4:  mov     %rax, (%rdx)
    RETURN_OK
SPEC_END is_slashable_attestation_data

.if (AttestationData__mem & 7) || (AttestationData__mem != 128)
.error "lantern_is_slashable_attestation_data compares AttestationData 8 bytes at a time"
.endif

/*
 * rbx state, rbp proposer slashing, r12 config, r13 scratch, r14 result, r15 proposer.
 * Locals: L predicate, L+8 epoch, L+16 domain type, L+24 domain (32),
 * L+56 signing root as a ByteList (56), L+112 index.
 */
SPEC_FUNCTION process_proposer_slashing
    ENTER 128
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
.if FORK >= FORK_FULU
    NEED_SCRATCH %r13, %rbx, 1, 9f
.else
    NEED_SCRATCH %r13, %rbx, 2, 9f              # slash_validator takes S(2)
.endif
    movq    $0, (%r14)
    mov     $LANTERN_INVALID_PROPOSER_SLASHING, %eax
    lea     (ProposerSlashing_signed_header_1 + SignedBeaconBlockHeader_message)(%rbp), %rsi
    lea     (ProposerSlashing_signed_header_2 + SignedBeaconBlockHeader_message)(%rbp), %rdi
    mov     BeaconBlockHeader_slot(%rsi), %rcx
    cmp     BeaconBlockHeader_slot(%rdi), %rcx  # assert header_1.slot == header_2.slot
    jne     6f
    mov     BeaconBlockHeader_proposer_index(%rsi), %rdx
    cmp     BeaconBlockHeader_proposer_index(%rdi), %rdx    # assert header_1.proposer_index == header_2.proposer_index
    jne     6f
    xor     %ecx, %ecx                      # assert header_1 != header_2
1:  mov     (%rsi,%rcx), %r8
    cmp     (%rdi,%rcx), %r8
    jne     2f
    add     $8, %rcx
    cmp     $BeaconBlockHeader__mem, %rcx
    jb      1b
    jmp     6f
2:  mov     $LANTERN_INVALID_VALIDATOR_INDEX, %eax
    cmp     (BeaconState_validators + 8)(%rbx), %rdx
    jae     6f
    mov     %rdx, (L + 112)(%rsp)
    VALIDATOR %r15, %rbx, %rdx
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     %r15, %rdi                      # assert is_slashable_validator(proposer, current epoch)
    lea     (L + 8)(%rsp), %rsi
    lea     L(%rsp), %rdx
    call    lantern_is_slashable_validator
    mov     $LANTERN_INVALID_PROPOSER_SLASHING, %eax
    cmpq    $0, L(%rsp)
    je      6f
    lea     L(%rsp), %rdi
    lea     ProposerSlashing_signed_header_1(%rbp), %rsi
    call    lantern_check_header_signature
    test    %rax, %rax
    jnz     3f
    lea     L(%rsp), %rdi
    lea     ProposerSlashing_signed_header_2(%rbp), %rsi
    call    lantern_check_header_signature
3:  CHECK_STATUS %r14, 7f, 8f
    mov     %rbx, %rdi                      # slash_validator(state, header_1.proposer_index)
    lea     (L + 112)(%rsp), %rsi
    xor     %edx, %edx
    mov     %r12, %rcx
    mov     %r13, %r8
    mov     %r14, %r9
    call    lantern_slash_validator
    jmp     7f
8:  xor     %eax, %eax
7:  LEAVE 128
6:  mov     %rax, (%r14)
    xor     %eax, %eax
    LEAVE 128
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 128
SPEC_END process_proposer_slashing

/*
 * L0 of lantern_process_proposer_slashing: check the signature of signed header rsi by
 * proposer r15, with state rbx and scratch r13. rdi points at the caller's locals: +8 epoch,
 * +16 domain type, +24 domain, +56 signing root as a ByteList. Returns rax: 0, a status,
 * or LANTERN_INVALID_PROPOSER_SLASHING. Locals: rsp+0 the caller's locals, rsp+8 the header.
 */
LOCAL_FUNCTION lantern_check_header_signature
    FRAME 16
    mov     %rdi, 0(%rsp)
    mov     %rsi, 8(%rsp)
    mov     (SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(%rsi), %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     %rax, 8(%rdi)                   # compute_epoch_at_slot(signed_header.message.slot)
    movl    $DOMAIN_BEACON_PROPOSER, 16(%rdi)
    lea     16(%rdi), %rsi
    lea     8(%rdi), %rdx
    lea     24(%rdi), %r8
    mov     %r13, %rcx
    mov     %rbx, %rdi
    call    lantern_get_domain
    test    %rax, %rax
    jnz     1f
    mov     0(%rsp), %rax
    ADDRESS %rdi, lantern_type_BeaconBlockHeader
    mov     8(%rsp), %rsi
    add     $SignedBeaconBlockHeader_message, %rsi
    lea     24(%rax), %rdx
    mov     %r13, %rcx
    lea     80(%rax), %r8
    call    lantern_compute_signing_root
    test    %rax, %rax
    jnz     1f
    mov     0(%rsp), %rax
    lea     Validator_pubkey(%r15), %rdi
    mov     8(%rsp), %rsi
    add     $SignedBeaconBlockHeader_signature, %rsi
    lea     56(%rax), %rdx
    mov     %r13, %rcx
    call    lantern_verify_root_signature
    test    %rax, %rax
    jnz     1f
    test    %rdx, %rdx
    jnz     1f
    mov     $LANTERN_INVALID_PROPOSER_SLASHING, %eax
1:  UNFRAME 16
END_FUNCTION lantern_check_header_signature

/*
 * rbx state, rbp attestation_1, r12 config, r13 scratch, r14 result, r15 cursor 1,
 * S7 cursor 2, S8 attestation_2, S9 slashed_any.
 * Locals: L predicate, L+8 epoch, L+16 index, L+24 end 1, L+32 end 2, L+40 scratch size.
 */
SPEC_FUNCTION process_attester_slashing
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rax
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    NEED_SCRATCH %r13, %rbx, 8, 9f
    movq    $0, (%r14)
    mov     (%r13), %rcx
    mov     %rcx, (L + 40)(%rsp)
    PART    %rbp, %rcx, %rax, AttesterSlashing_attestation_1
    PART    %rdx, %rcx, %rax, AttesterSlashing_attestation_2
    mov     %rdx, S8(%rsp)
    lea     IndexedAttestation_data(%rbp), %rdi     # assert is_slashable_attestation_data(data_1, data_2)
    lea     IndexedAttestation_data(%rdx), %rsi
    lea     L(%rsp), %rdx
    call    lantern_is_slashable_attestation_data
    mov     $LANTERN_INVALID_ATTESTER_SLASHING, %eax
    cmpq    $0, L(%rsp)
    je      6f
    mov     %rbx, %rdi                      # assert is_valid_indexed_attestation(state, attestation_1)
    mov     %rbp, %rsi
    mov     %r13, %rcx
    lea     L(%rsp), %r8
    mov     CONFIG_PUBKEY_CACHE(%r12), %rdx
    call    lantern_is_valid_indexed_attestation
    CHECK_STATUS %r14, 7f, 8f
    mov     $LANTERN_INVALID_ATTESTER_SLASHING, %eax
    cmpq    $0, L(%rsp)
    je      6f
    mov     (L + 40)(%rsp), %rax
    mov     %rax, (%r13)
    mov     %rbx, %rdi
    mov     S8(%rsp), %rsi
    mov     %r13, %rcx
    lea     L(%rsp), %r8
    mov     CONFIG_PUBKEY_CACHE(%r12), %rdx
    call    lantern_is_valid_indexed_attestation
    CHECK_STATUS %r14, 7f, 8f
    mov     $LANTERN_INVALID_ATTESTER_SLASHING, %eax
    cmpq    $0, L(%rsp)
    je      6f
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_current_epoch
    movq    $0, S9(%rsp)
    PART    %r15, %rcx, %rbp, IndexedAttestation_attesting_indices  # the sorted intersection, by merge
    lea     (%r15,%rcx,8), %rcx
    mov     %rcx, (L + 24)(%rsp)
    mov     S8(%rsp), %rax
    PART    %rdx, %rcx, %rax, IndexedAttestation_attesting_indices
    mov     %rdx, S7(%rsp)
    lea     (%rdx,%rcx,8), %rcx
    mov     %rcx, (L + 32)(%rsp)
1:  cmp     (L + 24)(%rsp), %r15
    jae     4f
    mov     S7(%rsp), %rdx
    cmp     (L + 32)(%rsp), %rdx
    jae     4f
    mov     (%r15), %rax
    mov     (%rdx), %rcx
    cmp     %rcx, %rax
    jb      2f
    ja      3f
    add     $8, %r15
    add     $8, %rdx
    mov     %rdx, S7(%rsp)
    mov     %rax, (L + 16)(%rsp)
    VALIDATOR %rdi, %rbx, %rax              # if is_slashable_validator(state.validators[index], epoch)
    lea     (L + 8)(%rsp), %rsi
    lea     L(%rsp), %rdx
    call    lantern_is_slashable_validator
    cmpq    $0, L(%rsp)
    je      1b
    mov     (L + 40)(%rsp), %rax
    mov     %rax, (%r13)
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    xor     %edx, %edx
    mov     %r12, %rcx
    mov     %r13, %r8
    mov     %r14, %r9
    call    lantern_slash_validator
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (%r14)
    jne     8f
    movq    $1, S9(%rsp)
    jmp     1b
2:  add     $8, %r15
    jmp     1b
3:  addq    $8, S7(%rsp)
    jmp     1b
4:  mov     $LANTERN_INVALID_ATTESTER_SLASHING, %eax    # assert slashed_any
    cmpq    $0, S9(%rsp)
    je      6f
8:  xor     %eax, %eax
7:  LEAVE 48
6:  mov     %rax, (%r14)
    xor     %eax, %eax
    LEAVE 48
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
SPEC_END process_attester_slashing
