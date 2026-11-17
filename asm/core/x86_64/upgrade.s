/*
 * Fork upgrades, x86-64. Requirements: docs/reference/fork-upgrades.md.
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
.set UP_DEPOSITS, 6                 /* electra: room for S8 entries, appended after the parts */

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

/* Copy the fixed field name of the state before rbx to the new state r14. */
.macro UP_COPY_FIELD name
    .if BeaconState_\name\()__mem != PRE_BeaconState_\name\()__mem
    .error "UP_FIXED: a field changes its size"
    .endif
    lea     BeaconState_\name(%r14), %rdi
    lea     PRE_BeaconState_\name(%rbx), %rsi
    MOVQ    %rdx, BeaconState_\name\()__mem
    call    lantern_copy
.endm

/* rax = the entries of the new part name. */
.macro UP_COUNT name, how
.if (\how) == UP_COPY
    mov     (PRE_BeaconState_\name + 8)(%rbx), %rax
.elseif (\how) == UP_ZEROS
    mov     (PRE_BeaconState_validators + 8)(%rbx), %rax
.elseif (\how) == UP_DEPOSITS
    mov     S8(%rsp), %rax
.elseif (\how) == UP_EMPTY
    xor     %eax, %eax
.else
    mov     $1, %eax                        # one header value
.endif
.endm

/* rcx = the bytes of a part of rax entries of stride with the room at room of StateRoom rbp, rounded up to 8. */
.macro UP_CAPACITY stride, room
.if \stride
    .if (\room) >= 0
    mov     \room(%rbp), %rcx
    add     %rax, %rcx
    .else
    mov     %rax, %rcx
    .endif
    imul    $(\stride), %rcx, %rcx
    add     $7, %rcx
    and     $-8, %rcx
.else
    MOVQ    %rcx, HEADER_ROOM
.endif
.endm

.macro UP_SIZE_PART name, stride, room, how
    UP_COUNT \name, \how
    UP_CAPACITY \stride, \room
    add     %rcx, %r15
.endm

/* Write the part name of the new state r14 at cursor r15, from the state before rbx, and move the cursor. */
.macro UP_WRITE_PART name, stride, room, how
    UP_COUNT \name, \how
    UP_CAPACITY \stride, \room
    mov     %r15, BeaconState_\name(%r14)
.if (\how) == UP_DEPOSITS
    movq    $0, (BeaconState_\name + 8)(%r14)
.else
    mov     %rax, (BeaconState_\name + 8)(%r14)
.endif
    lea     (%r14,%r15), %rdi
    add     %rcx, %r15
.if (\how) == UP_COPY
    PART    %rsi, %rdx, %rbx, PRE_BeaconState_\name
    .if \stride
    imul    $(\stride), %rdx, %rdx
    .else
    mov     (%rsi), %rdx                    # a nested value: its size
    .endif
    call    lantern_copy
.elseif (\how) == UP_ZEROS
    imul    $(\stride), %rax, %rsi
    call    lantern_zero
.elseif (\how) == UP_HEADER_EMPTY
    call    upgrade_empty_header
.elseif (\how) == UP_HEADER
    PART    %rsi, %rdx, %rbx, PRE_BeaconState_latest_execution_payload_header
    call    upgrade_header
.endif
.endm

.if FORK == FORK_BELLATRIX
/* ExecutionPayloadHeader() at rdi. Locals: rsp+0 the header. */
LOCAL_FUNCTION upgrade_empty_header
    FRAME 16
    mov     %rdi, 0(%rsp)
    MOVQ    %rsi, ExecutionPayloadHeader__fixed
    call    lantern_zero
    mov     0(%rsp), %rdi
    movq    $ExecutionPayloadHeader__fixed, (%rdi)  # its size
    movq    $ExecutionPayloadHeader__fixed, ExecutionPayloadHeader_extra_data(%rdi)    # the empty extra_data part, after the fixed fields
    UNFRAME 16
END_FUNCTION upgrade_empty_header
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
    mov     0(%rsp), %rdi
    mov     8(%rsp), %rsi
    add     $ExecutionPayloadHeader_\name, %rdi
    add     $PRE_ExecutionPayloadHeader_\name, %rsi
    mov     $ExecutionPayloadHeader_\name\()__mem, %edx
    call    lantern_copy
.endm

/* The header of the fork at rdi from the header rsi of the fork before: its fields and extra_data, the new fields zero. */
LOCAL_FUNCTION upgrade_header
    FRAME 16
    mov     %rdi, 0(%rsp)
    mov     %rsi, 8(%rsp)
    MOVQ    %rsi, ExecutionPayloadHeader__fixed
    call    lantern_zero
    UP_HEADER_FIELDS UP_COPY_HEADER_FIELD
    mov     0(%rsp), %rdi
    mov     8(%rsp), %rcx
    PART    %rsi, %rdx, %rcx, PRE_ExecutionPayloadHeader_extra_data
    movq    $ExecutionPayloadHeader__fixed, ExecutionPayloadHeader_extra_data(%rdi)
    mov     %rdx, (ExecutionPayloadHeader_extra_data + 8)(%rdi)
    lea     (ExecutionPayloadHeader__fixed + 7)(%rdx), %rax
    and     $-8, %rax
    mov     %rax, (%rdi)                    # its size
    add     $ExecutionPayloadHeader__fixed, %rdi
    call    lantern_copy
    UNFRAME 16
END_FUNCTION upgrade_header
.endif

.if FORK == FORK_ELECTRA
/* L0: rax = the pending deposits that upgrade_to_electra appends for the state before rdi. A leaf. */
LOCAL_FUNCTION upgrade_deposit_count
    UNWIND_END_PROLOGUE
    PART    %rsi, %rcx, %rdi, PRE_BeaconState_validators
    PART    %rdx, %r8, %rdi, PRE_BeaconState_balances
    xor     %eax, %eax
    MOVQ    %r9, MIN_ACTIVATION_BALANCE
1:  test    %rcx, %rcx
    jz      3f
    cmpq    $-1, Validator_activation_epoch(%rsi)   # activation_epoch == FAR_FUTURE_EPOCH: a pending deposit of its balance
    je      2f
    cmpb    $COMPOUNDING_WITHDRAWAL_PREFIX, Validator_withdrawal_credentials(%rsi)
    jne     25f
    cmp     %r9, (%rdx)                     # a compounding validator's excess above MIN_ACTIVATION_BALANCE
    jbe     25f
2:  inc     %rax
25: add     $Validator__mem, %rsi
    add     $8, %rdx
    dec     %rcx
    jmp     1b
3:  ret
END_FUNCTION upgrade_deposit_count

/* Flags: ja when the key of validator index a is above that of b; the key is (activation_eligibility_epoch, index). Uses r10, r11. */
.macro ELIGIBILITY_CMP a, b
    mov     \a, %r10
    shl     $7, %r10
    mov     Validator_activation_eligibility_epoch(%rdx,%r10), %r10
    mov     \b, %r11
    shl     $7, %r11
    mov     Validator_activation_eligibility_epoch(%rdx,%r11), %r11
    cmp     %r11, %r10
    jne     95f
    cmp     \b, \a
95:
.endm

/* Sift the entry at root down the heap of entries below end, at rdi, by key. Uses rax, rbx, rbp, r8-r11. */
.macro ELIGIBILITY_SIFT root, end
97: lea     1(\root,\root), %r8             # child = 2 * root + 1
    cmp     \end, %r8
    jae     98f
    mov     (%rdi,%r8,8), %r9
    lea     1(%r8), %rbx
    cmp     \end, %rbx
    jae     96f
    mov     (%rdi,%rbx,8), %rbp
    ELIGIBILITY_CMP %rbp, %r9               # the larger child
    jbe     96f
    mov     %rbx, %r8
    mov     %rbp, %r9
96: mov     (%rdi,\root,8), %rax
    ELIGIBILITY_CMP %rax, %r9
    jae     98f
    mov     %r9, (%rdi,\root,8)
    mov     %rax, (%rdi,%r8,8)
    mov     %r8, \root
    jmp     97b
98:
.endm

/* Sort the rsi validator indices at rdi by (activation_eligibility_epoch, index) of the validators at rdx (heapsort). r12 the loop. */
LOCAL_FUNCTION sort_by_eligibility
    ENTER 0
    cmp     $2, %rsi
    jb      9f
    mov     %rsi, %r12
    shr     $1, %r12
1:  test    %r12, %r12
    jz      2f
    dec     %r12
    mov     %r12, %rcx
    ELIGIBILITY_SIFT %rcx, %rsi
    jmp     1b
2:  mov     %rsi, %r12
3:  dec     %r12
    jz      9f
    mov     (%rdi), %rax
    mov     (%rdi,%r12,8), %r9
    mov     %r9, (%rdi)
    mov     %rax, (%rdi,%r12,8)
    xor     %ecx, %ecx
    ELIGIBILITY_SIFT %rcx, %r12
    jmp     3b
9:  LEAVE 0
END_FUNCTION sort_by_eligibility

.if (Validator_pubkey != PendingDeposit_pubkey) || (Validator_withdrawal_credentials != PendingDeposit_withdrawal_credentials) || (PendingDeposit_amount != 80)
.error "upgrade_to_electra copies the pubkey and credentials of a Validator into a PendingDeposit in one block"
.endif
.endif

.if FORK >= FORK_ALTAIR
/* rbx pre, rbp room, r12 size, r15 total, S8 electra: pending deposits. */
SPEC_FUNCTION upgrade_size
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
.if FORK == FORK_ELECTRA
    call    upgrade_deposit_count
    mov     %rax, S8(%rsp)
.endif
    MOVQ    %r15, BeaconState__fixed
    UP_PARTS UP_SIZE_PART
    mov     %r15, (%r12)
    xor     %eax, %eax
    LEAVE 16
SPEC_END upgrade_size
.endif

.if FORK == FORK_ALTAIR
/*
 * rbx state, rbp pre, r12 scratch, r13 the entry, r14 entries left, r15 committee,
 * S7 flags mask, S8 scratch size, S9 the size callees get. Locals: L flags (FLAGS_BYTES).
 */
SPEC_FUNCTION translate_participation
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    NEED_SCRATCH %r12, %rbx, 2, 9f
    mov     (%r12), %rax
    mov     %rax, S8(%rsp)
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    SCRATCH_LIST %r15, %r12, %rax, 0, %rcx  # the committee: the last list
    SCRATCH_GIVE %r12, S8(%rsp), 1, %rcx
    mov     (%r12), %rax
    mov     %rax, S9(%rsp)
    PART    %r13, %r14, %rbp, PRE_BeaconState_previous_epoch_attestations
1:  test    %r14, %r14                      # for attestation in pending_attestations
    jz      8f
    movq    $FLAGS_BYTES, L(%rsp)
    mov     %rbx, %rdi                      # participation_flag_indices = get_attestation_participation_flag_indices(state, data, inclusion_delay)
    lea     PRE_PendingAttestation_data(%r13), %rsi
    lea     PRE_PendingAttestation_inclusion_delay(%r13), %rdx
    lea     L(%rsp), %rcx
    call    lantern_get_attestation_participation_flag_indices
    test    %rax, %rax
    jnz     7f
    xor     %eax, %eax                      # the flags as one mask: add_flag of each
    mov     (L + LIST_COUNT)(%rsp), %rcx
    lea     (L + LIST_FIXED)(%rsp), %rdx
2:  test    %rcx, %rcx
    jz      3f
    mov     (%rdx), %r8
    add     $8, %rdx
    bts     %r8, %rax
    dec     %rcx
    jmp     2b
3:  mov     %rax, S7(%rsp)
    mov     S9(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi                      # committee = get_beacon_committee(state, data.slot, data.index)
    lea     (PRE_PendingAttestation_data + PRE_AttestationData_slot)(%r13), %rsi
    lea     (PRE_PendingAttestation_data + PRE_AttestationData_index)(%r13), %rdx
    mov     %r12, %rcx
    mov     %r15, %r8
    call    lantern_get_beacon_committee
    test    %rax, %rax
    jnz     7f
    PART    %rsi, %rdx, %r13, PRE_PendingAttestation_aggregation_bits
    PART    %rdi, %r8, %rbx, BeaconState_previous_epoch_participation
    mov     LIST_COUNT(%r15), %r9
    lea     LIST_FIXED(%r15), %r10
    mov     S7(%rsp), %rax
    xor     %ecx, %ecx
4:  cmp     %r9, %rcx                       # each committee member whose aggregation bit is set
    jae     6f
    cmp     %rdx, %rcx
    jae     6f
    bt      %rcx, (%rsi)
    jnc     5f
    mov     (%r10,%rcx,8), %r11
    or      %al, (%rdi,%r11)
5:  inc     %rcx
    jmp     4b
6:  mov     (%r13), %rax                    # the next nested value
    add     %rax, %r13
    dec     %r14
    jmp     1b
8:  xor     %eax, %eax
7:  mov     S8(%rsp), %rcx
    mov     %rcx, (%r12)
    LEAVE 64
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 64
SPEC_END translate_participation
.endif

.if FORK >= FORK_FULU
/* rbx state, rbp scratch, r12 out, r13 scratch size, r14 i. Locals: L epoch. */
SPEC_FUNCTION initialize_proposer_lookahead
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    NEED_SCRATCH %rbp, %rbx, 2, 9f
    mov     (%rbp), %r13
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    xor     %r14d, %r14d
1:  cmp     $(MIN_SEED_LOOKAHEAD + 1), %r14 # for i in range(MIN_SEED_LOOKAHEAD + 1)
    jae     8f
    mov     %r13, (%rbp)
    mov     %rbx, %rdi                      # lookahead.extend(get_beacon_proposer_indices(state, current_epoch + i))
    lea     L(%rsp), %rsi
    mov     %rbp, %rdx
    imul    $(8 * SLOTS_PER_EPOCH), %r14, %rcx
    add     %r12, %rcx
    call    lantern_get_beacon_proposer_indices
    test    %rax, %rax
    jnz     7f
    addq    $1, L(%rsp)
    jc      6f
    inc     %r14
    jmp     1b
8:  xor     %eax, %eax
7:  mov     %r13, (%rbp)
    LEAVE 16
6:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    jmp     7b
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END initialize_proposer_lookahead
.endif

/*
 * The upgrade of the fork, under its spec name.
 * rbx pre, rbp room, r12 config, r13 scratch, r14 out, r15 cursor, S7 validator count,
 * S8 electra: pending deposits, S9 scratch size, S10 electra: the pre_activation list.
 * Locals: L size, L+8 epoch, L+16 a number, L+24 index, L+32 PendingDeposit (PendingDeposit__mem).
 */
.macro UPGRADE_FUNCTION name, version
SPEC_FUNCTION \name
    ENTER 240
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     (%r13), %rax
    mov     %rax, S9(%rsp)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    lea     L(%rsp), %rdx
    call    lantern_upgrade_size
    mov     L(%rsp), %rax
    cmp     %rax, (%r14)
    jb      9f
.if FORK == FORK_ALTAIR
    NEED_SCRATCH_B %r13, %rbx, 2, SYNC_COMMITTEE_SCRATCH, 9f
.elseif FORK == FORK_ELECTRA || FORK == FORK_FULU
    NEED_SCRATCH %r13, %rbx, 2, 9f
.endif
    mov     (PRE_BeaconState_validators + 8)(%rbx), %rax
    mov     %rax, S7(%rsp)
.if FORK == FORK_ELECTRA
    mov     %rbx, %rdi
    call    upgrade_deposit_count
    mov     %rax, S8(%rsp)
.endif
    lea     8(%r14), %rdi                   # the fixed part, after out's own size: zero, then the shared fields
    MOVQ    %rsi, BeaconState__fixed - 8
    call    lantern_zero
    UP_FIXED UP_COPY_FIELD
    mov     (PRE_BeaconState_fork + PRE_Fork_current_version)(%rbx), %eax  # fork = Fork(pre.fork.current_version, the fork's version, epoch)
    mov     %eax, (BeaconState_fork + Fork_previous_version)(%r14)
    mov     \version(%r12), %eax
    mov     %eax, (BeaconState_fork + Fork_current_version)(%r14)
    mov     PRE_BeaconState_slot(%rbx), %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     %rax, (BeaconState_fork + Fork_epoch)(%r14)
    mov     %rax, (L + 8)(%rsp)
    MOVQ    %r15, BeaconState__fixed        # the parts, in field order
    UP_PARTS UP_WRITE_PART
.if FORK == FORK_ALTAIR
    mov     S9(%rsp), %rax
    mov     %rax, (%r13)
    mov     %r14, %rdi                      # translate_participation(post, pre.previous_epoch_attestations)
    mov     %rbx, %rsi
    mov     %r13, %rdx
    call    lantern_translate_participation
    test    %rax, %rax
    jnz     7f
    mov     S9(%rsp), %rax
    mov     %rax, (%r13)
    mov     %r14, %rdi                      # post.current_sync_committee = get_next_sync_committee(post)
    mov     %r13, %rsi
    lea     BeaconState_current_sync_committee(%r14), %rdx
    call    lantern_get_next_sync_committee
    test    %rax, %rax
    jnz     7f
    mov     S9(%rsp), %rax
    mov     %rax, (%r13)
    mov     %r14, %rdi                      # post.next_sync_committee = get_next_sync_committee(post)
    mov     %r13, %rsi
    lea     BeaconState_next_sync_committee(%r14), %rdx
    call    lantern_get_next_sync_committee
    test    %rax, %rax
    jnz     7f
.elseif FORK == FORK_ELECTRA
    lea     (L + 8)(%rsp), %rdi             # earliest_exit_epoch = compute_activation_exit_epoch(epoch)
    lea     (L + 16)(%rsp), %rsi
    call    lantern_compute_activation_exit_epoch
    test    %rax, %rax
    jnz     7f
    mov     (L + 16)(%rsp), %rax
    mov     %rax, BeaconState_earliest_consolidation_epoch(%r14)
    PART    %rsi, %rcx, %r14, BeaconState_validators
1:  test    %rcx, %rcx                      # max with each exit_epoch other than FAR_FUTURE_EPOCH
    jz      2f
    mov     Validator_exit_epoch(%rsi), %rdx
    add     $Validator__mem, %rsi
    dec     %rcx
    cmp     $-1, %rdx
    je      1b
    cmp     %rax, %rdx
    cmova   %rdx, %rax
    jmp     1b
2:  add     $1, %rax                        # earliest_exit_epoch += 1
    jc      6f
    mov     %rax, BeaconState_earliest_exit_epoch(%r14)
    movq    $-1, BeaconState_deposit_requests_start_index(%r14)   # UNSET_DEPOSIT_REQUESTS_START_INDEX
    mov     S9(%rsp), %rax
    mov     %rax, (%r13)
    mov     %r14, %rdi                      # exit_balance_to_consume = get_activation_exit_churn_limit(post)
    mov     %r12, %rsi
    mov     %r13, %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_get_activation_exit_churn_limit
    test    %rax, %rax
    jnz     7f
    mov     (L + 16)(%rsp), %rax
    mov     %rax, BeaconState_exit_balance_to_consume(%r14)
    mov     S9(%rsp), %rax
    mov     %rax, (%r13)
    mov     %r14, %rdi                      # consolidation_balance_to_consume = get_consolidation_churn_limit(post)
    mov     %r12, %rsi
    mov     %r13, %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_get_consolidation_churn_limit
    test    %rax, %rax
    jnz     7f
    mov     (L + 16)(%rsp), %rax
    mov     %rax, BeaconState_consolidation_balance_to_consume(%r14)
    mov     S7(%rsp), %rcx
    SCRATCH_LIST %rax, %r13, S9(%rsp), 0, %rcx   # pre_activation: the last list of scratch
    mov     %rax, S10(%rsp)
    PART    %rsi, %rcx, %r14, BeaconState_validators
    lea     LIST_FIXED(%rax), %rdi
    xor     %edx, %edx
3:  cmp     %rcx, %rdx                      # the validators with activation_epoch FAR_FUTURE_EPOCH, in index order
    jae     4f
    cmpq    $-1, Validator_activation_epoch(%rsi)
    jne     35f
    mov     %rdx, (%rdi)
    add     $8, %rdi
35: add     $Validator__mem, %rsi
    inc     %rdx
    jmp     3b
4:  mov     S10(%rsp), %rax
    lea     LIST_FIXED(%rax), %rsi
    sub     %rsi, %rdi
    shr     $3, %rdi
    mov     %rdi, LIST_COUNT(%rax)
    mov     %rdi, %rsi                      # sorted by (activation_eligibility_epoch, index)
    lea     LIST_FIXED(%rax), %rdi
    PART    %rdx, %r8, %r14, BeaconState_validators
    call    sort_by_eligibility
    lea     (L + 32 + PendingDeposit_signature)(%rsp), %rdi    # signature: G2_POINT_AT_INFINITY; slot: GENESIS_SLOT
    mov     $96, %esi
    call    lantern_zero
    movb    $0xc0, (L + 32 + PendingDeposit_signature)(%rsp)
    movq    $0, (L + 32 + PendingDeposit_slot)(%rsp)
    mov     S10(%rsp), %rax
    mov     LIST_COUNT(%rax), %rcx
    lea     LIST_FIXED(%rax,%rcx,8), %rcx
    mov     %rcx, (L + 16)(%rsp)            # the end of the list
    lea     LIST_FIXED(%rax), %r15
5:  cmp     (L + 16)(%rsp), %r15
    jae     55f
    mov     (%r15), %rax                    # for index in pre_activation
    add     $8, %r15
    PART    %rsi, %rcx, %r14, BeaconState_balances
    mov     (%rsi,%rax,8), %rdx
    movq    $0, (%rsi,%rax,8)               # post.balances[index] = 0
    mov     %rdx, (L + 32 + PendingDeposit_amount)(%rsp)
    PART    %rsi, %rcx, %r14, BeaconState_validators
    shl     $7, %rax
    add     %rax, %rsi
    movq    $0, Validator_effective_balance(%rsi)
    movq    $-1, Validator_activation_eligibility_epoch(%rsi)
    lea     (L + 32)(%rsp), %rdi            # PendingDeposit(validator.pubkey, validator.withdrawal_credentials, balance, ...)
    mov     $PendingDeposit_amount, %edx
    call    lantern_copy
    mov     %r14, %rdi
    lea     (L + 32)(%rsp), %rsi
    call    append_pending_deposit
    test    %rax, %rax
    jnz     7f
    jmp     5b
55: xor     %r15d, %r15d
56: cmp     S7(%rsp), %r15                  # queue_excess_active_balance for each compounding validator
    jae     8f
    PART    %rsi, %rcx, %r14, BeaconState_validators
    mov     %r15, %rax
    shl     $7, %rax
    cmpb    $COMPOUNDING_WITHDRAWAL_PREFIX, Validator_withdrawal_credentials(%rsi,%rax)
    jne     57f
    mov     %r15, (L + 24)(%rsp)
    mov     %r14, %rdi
    lea     (L + 24)(%rsp), %rsi
    call    lantern_queue_excess_active_balance
    test    %rax, %rax
    jnz     7f
57: inc     %r15
    jmp     56b
.elseif FORK == FORK_FULU
    mov     S9(%rsp), %rax
    mov     %rax, (%r13)
    mov     %r14, %rdi                      # post.proposer_lookahead = initialize_proposer_lookahead(post)
    mov     %r13, %rsi
    lea     BeaconState_proposer_lookahead(%r14), %rdx
    call    lantern_initialize_proposer_lookahead
    test    %rax, %rax
    jnz     7f
.endif
8:  xor     %eax, %eax
7:  mov     S9(%rsp), %rcx
    mov     %rcx, (%r13)
    LEAVE 240
6:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    jmp     7b
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
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
