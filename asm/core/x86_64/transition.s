/*
 * The block steps, the block, slots and the state transition, x86-64.
 * Requirements: docs/reference/block-processing.md and docs/reference/state-transition.md.
 */

/* ---------------------------------------------------------------- RANDAO and eth1 data */

/*
 * rbx state, rbp body, r12 config, r13 scratch, r14 result, r15 proposer.
 * Locals: L epoch, L+8 proposer index, L+16 domain type, L+24 domain (32),
 * L+56 signing root as a ByteList (56), L+112 sha256(reveal), L+144 mix.
 */
SPEC_FUNCTION process_randao
    ENTER 176
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
.if FORK >= FORK_FULU
    NEED_SCRATCH %r13, %rbx, 0, 9f
.else
    NEED_SCRATCH %r13, %rbx, 2, 9f              # get_beacon_proposer_index takes S(2)
.endif
    movq    $0, (%r14)
    mov     (%r13), %r15
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     %rbx, %rdi
.if FORK >= FORK_FULU
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_beacon_proposer_index
.else
    mov     %r13, %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_get_beacon_proposer_index
    mov     %r15, (%r13)
    test    %rax, %rax
    jz      1f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      7f
    jmp     6f
1:
.endif
    mov     (L + 8)(%rsp), %rcx
    mov     $LANTERN_INVALID_VALIDATOR_INDEX, %eax
    cmp     (BeaconState_validators + 8)(%rbx), %rcx
    jae     6f
    VALIDATOR %r15, %rbx, %rcx
    movl    $DOMAIN_RANDAO, (L + 16)(%rsp)  # signing_root = compute_signing_root(epoch, get_domain(state, DOMAIN_RANDAO))
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    lea     L(%rsp), %rdx
    mov     %r13, %rcx
    lea     (L + 24)(%rsp), %r8
    call    lantern_get_domain
    test    %rax, %rax
    jnz     7f
    ADDRESS %rdi, lantern_type_Uint64
    lea     L(%rsp), %rsi
    lea     (L + 24)(%rsp), %rdx
    mov     %r13, %rcx
    lea     (L + 80)(%rsp), %r8
    call    lantern_compute_signing_root
    test    %rax, %rax
    jnz     7f
    lea     Validator_pubkey(%r15), %rdi    # assert bls.Verify(proposer.pubkey, signing_root, body.randao_reveal)
    lea     BeaconBlockBody_randao_reveal(%rbp), %rsi
    lea     (L + 56)(%rsp), %rdx
    mov     %r13, %rcx
    call    verify_root_signature
    test    %rax, %rax
    jnz     7f
    mov     $LANTERN_INVALID_RANDAO_REVEAL, %eax
    test    %rdx, %rdx
    jz      6f
    lea     BeaconBlockBody_randao_reveal(%rbp), %rdi   # mix = xor(get_randao_mix(state, epoch), sha256(randao_reveal))
    mov     $96, %esi
    lea     (L + 112)(%rsp), %rdx
    call    sha256_short
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 144)(%rsp), %rdx
    call    lantern_get_randao_mix
    mov     L(%rsp), %rax
    and     $(EPOCHS_PER_HISTORICAL_VECTOR - 1), %eax
    shl     $5, %rax
    lea     BeaconState_randao_mixes(%rbx,%rax), %rdx
    lea     (L + 144)(%rsp), %rdi
    lea     (L + 112)(%rsp), %rsi
    call    lantern_xor
    xor     %eax, %eax
7:  LEAVE 176
6:  mov     %rax, (%r14)
    xor     %eax, %eax
    LEAVE 176
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 176
SPEC_END process_randao

/* rbx state, rbp body, r12 result. */
SPEC_FUNCTION process_eth1_data
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %r8, %r12
    mov     BeaconState_eth1_data_votes(%rbx), %rax
    mov     (BeaconState_eth1_data_votes + 8)(%rbx), %rcx
    mov     BeaconState_validators(%rbx), %rdx
    sub     %rax, %rdx
    lea     1(%rcx), %rsi
    imul    $Eth1Data__mem, %rsi, %rsi
    cmp     %rdx, %rsi
    ja      9f
    movq    $0, (%r12)
    lea     1(%rcx), %rsi                   # state.eth1_data_votes.append(body.eth1_data)
    mov     %rsi, (BeaconState_eth1_data_votes + 8)(%rbx)
    imul    $Eth1Data__mem, %rcx, %rcx
    add     %rcx, %rax
    lea     (%rbx,%rax), %rdi
    lea     BeaconBlockBody_eth1_data(%rbp), %rsi
    mov     $Eth1Data__mem, %edx
    call    lantern_copy
    PART    %rsi, %rcx, %rbx, BeaconState_eth1_data_votes   # state.eth1_data_votes.count(body.eth1_data)
    lea     BeaconBlockBody_eth1_data(%rbp), %rdi
    xor     %eax, %eax
1:  test    %rcx, %rcx
    jz      4f
    xor     %edx, %edx
2:  mov     (%rsi,%rdx), %r8
    cmp     (%rdi,%rdx), %r8
    jne     3f
    add     $8, %rdx
    cmp     $Eth1Data__mem, %rdx
    jb      2b
    inc     %rax
3:  add     $Eth1Data__mem, %rsi
    dec     %rcx
    jmp     1b
4:  shl     $1, %rax
    cmp     $(EPOCHS_PER_ETH1_VOTING_PERIOD * SLOTS_PER_EPOCH), %rax
    jbe     8f
    lea     BeaconState_eth1_data(%rbx), %rdi   # state.eth1_data = body.eth1_data
    lea     BeaconBlockBody_eth1_data(%rbp), %rsi
    mov     $Eth1Data__mem, %edx
    call    lantern_copy
8:  xor     %eax, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END process_eth1_data

.if Eth1Data__mem != 72
.error "lantern_process_eth1_data compares Eth1Data 8 bytes at a time"
.endif

/* ---------------------------------------------------------------- Operations */

/*
 * Call fn(state, entry, config, scratch, result) for each entry of a list of fixed size entries
 * of value (a register). rbx, r12, r13, r14 hold the arguments, r15 the scratch size; S7 the entry, S8 entries left.
 */
.macro FOR_FIXED value, ref, stride, fn
    PART    %rax, %rcx, \value, \ref
    mov     %rax, S7(%rsp)
    mov     %rcx, S8(%rsp)
91: cmpq    $0, S8(%rsp)
    je      92f
    mov     %r15, (%r13)
    mov     %rbx, %rdi
    mov     S7(%rsp), %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    call    \fn
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (%r14)
    jne     8f
    addq    $(\stride), S7(%rsp)
    decq    S8(%rsp)
    jmp     91b
92:
.endm

/* The same for a list of nested values: each starts with its size. */
.macro FOR_VARIABLE value, ref, fn
    PART    %rax, %rcx, \value, \ref
    mov     %rax, S7(%rsp)
    mov     %rcx, S8(%rsp)
91: cmpq    $0, S8(%rsp)
    je      92f
    mov     %r15, (%r13)
    mov     %rbx, %rdi
    mov     S7(%rsp), %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    call    \fn
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (%r14)
    jne     8f
    mov     S7(%rsp), %rax
    add     (%rax), %rax
    mov     %rax, S7(%rsp)
    decq    S8(%rsp)
    jmp     91b
92:
.endm

/* rbx state, rbp body, r12 config, r13 scratch, r14 result, r15 scratch size, S7 entry, S8 left, S9 requests. */
SPEC_FUNCTION process_operations
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     (%r13), %r15
    movq    $0, (%r14)
.if FORK >= FORK_FULU
    cmpq    $0, (BeaconBlockBody_deposits + 8)(%rbp)    # assert len(body.deposits) == 0
    je      1f
.elseif FORK == FORK_ELECTRA
    mov     (BeaconState_eth1_data + Eth1Data_deposit_count)(%rbx), %rax
    mov     BeaconState_deposit_requests_start_index(%rbx), %rdx
    cmp     %rdx, %rax
    cmova   %rdx, %rax                      # eth1_deposit_index_limit
    xor     %ecx, %ecx
    sub     BeaconState_eth1_deposit_index(%rbx), %rax
    cmovbe  %rcx, %rax                      # limit - eth1_deposit_index while below the limit, else 0
    mov     $MAX_DEPOSITS, %edx
    cmp     %rdx, %rax
    cmova   %rdx, %rax
    cmp     (BeaconBlockBody_deposits + 8)(%rbp), %rax  # assert len(body.deposits) == that
    je      1f
.else
    mov     (BeaconState_eth1_data + Eth1Data_deposit_count)(%rbx), %rax
    mov     $LANTERN_INVALID_OVERFLOW, %ecx
    sub     BeaconState_eth1_deposit_index(%rbx), %rax  # state.eth1_data.deposit_count - state.eth1_deposit_index
    jb      2f
    mov     $MAX_DEPOSITS, %edx
    cmp     %rdx, %rax
    cmova   %rdx, %rax
    cmp     (BeaconBlockBody_deposits + 8)(%rbp), %rax  # assert len(body.deposits) == min(MAX_DEPOSITS, ...)
    je      1f
.endif
    mov     $LANTERN_INVALID_DEPOSITS, %ecx
2:  mov     %rcx, (%r14)
    jmp     8f
1:  FOR_FIXED %rbp, BeaconBlockBody_proposer_slashings, ProposerSlashing__mem, lantern_process_proposer_slashing
    FOR_VARIABLE %rbp, BeaconBlockBody_attester_slashings, lantern_process_attester_slashing
    FOR_VARIABLE %rbp, BeaconBlockBody_attestations, lantern_process_attestation
.if FORK < FORK_FULU
    FOR_FIXED %rbp, BeaconBlockBody_deposits, Deposit__mem, lantern_process_deposit
.endif
    FOR_FIXED %rbp, BeaconBlockBody_voluntary_exits, SignedVoluntaryExit__mem, lantern_process_voluntary_exit
.if FORK >= FORK_CAPELLA
    FOR_FIXED %rbp, BeaconBlockBody_bls_to_execution_changes, SignedBLSToExecutionChange__mem, lantern_process_bls_to_execution_change
.endif
.if FORK >= FORK_ELECTRA
    PART    %rax, %rcx, %rbp, BeaconBlockBody_execution_requests
    mov     %rax, S9(%rsp)
    mov     S9(%rsp), %rdx
    FOR_FIXED %rdx, ExecutionRequests_deposits, DepositRequest__mem, lantern_process_deposit_request
    mov     S9(%rsp), %rdx
    FOR_FIXED %rdx, ExecutionRequests_withdrawals, WithdrawalRequest__mem, lantern_process_withdrawal_request
    mov     S9(%rsp), %rdx
    FOR_FIXED %rdx, ExecutionRequests_consolidations, ConsolidationRequest__mem, lantern_process_consolidation_request
.endif
8:  xor     %eax, %eax
7:  LEAVE 16
SPEC_END process_operations

/* ---------------------------------------------------------------- The block */

/* rax = free entries of one list of state rdi: (next part offset - offset) // stride - count. Uses rcx, rdx. */
.macro FREE ref, next, stride
    mov     (\next)(%rdi), %rax
    sub     (\ref)(%rdi), %rax
    xor     %edx, %edx
    mov     $(\stride), %ecx
    div     %rcx
    sub     ((\ref) + 8)(%rdi), %rax
.endm

.if FORK >= FORK_ELECTRA
/*
 * L0: rax = LANTERN_OK when state rdi has room for the appends of the execution requests of
 * block body rsi and r10 more pending deposits, else LANTERN_BUFFER_TOO_SMALL. A leaf.
 */
LOCAL_FUNCTION requests_room
    UNWIND_END_PROLOGUE
    PART    %r8, %r9, %rsi, BeaconBlockBody_execution_requests
    mov     (ExecutionRequests_deposits + 8)(%r8), %rsi
    mov     (ExecutionRequests_withdrawals + 8)(%r8), %r9
    mov     (ExecutionRequests_consolidations + 8)(%r8), %r8
    FREE    BeaconState_eth1_data_votes, BeaconState_validators, Eth1Data__mem
    cmp     $1, %rax
    jl      9f
    FREE    BeaconState_pending_deposits, BeaconState_pending_partial_withdrawals, PendingDeposit__mem
    lea     (%r10,%rsi), %rcx               # deposit requests, and the excess of each switch to compounding
    add     %r8, %rcx
    cmp     %rcx, %rax
    jl      9f
    FREE    BeaconState_pending_partial_withdrawals, BeaconState_pending_consolidations, PendingPartialWithdrawal__mem
    cmp     %r9, %rax
    jl      9f
    mov     (%rdi), %rax                    # the last part ends at the value's end
    sub     BeaconState_pending_consolidations(%rdi), %rax
    shr     $4, %rax
    sub     (BeaconState_pending_consolidations + 8)(%rdi), %rax
    cmp     %r8, %rax
    jl      9f
    xor     %eax, %eax
    ret
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    ret
END_FUNCTION requests_room

.if FORK == FORK_ELECTRA
/*
 * L0: rax = LANTERN_OK when state rdi has room for the appends of block body rsi, else
 * LANTERN_BUFFER_TOO_SMALL: a validator and a pending deposit for each deposit, and the
 * appends of the execution requests. rbx state, rbp body.
 */
LOCAL_FUNCTION block_room
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    call    validator_room
    mov     (BeaconBlockBody_deposits + 8)(%rbp), %r10
    cmp     %r10, %rax
    jb      9f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    requests_room
    LEAVE 0
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
END_FUNCTION block_room
.else
/* L0: requests_room with no deposits. */
LOCAL_FUNCTION block_room
    UNWIND_END_PROLOGUE
    xor     %r10d, %r10d
    jmp     requests_room
END_FUNCTION block_room
.endif

.else
.if FORK == FORK_PHASE0
/* rax = the free bytes of a list of nested values of state rbx: its end offset rcx - its start - its entries' sizes. Uses rdx, r8, r9. */
.macro FREE_NESTED ref
    mov     (\ref)(%rbx), %rdx
    mov     ((\ref) + 8)(%rbx), %r8
    mov     %rcx, %rax
    sub     %rdx, %rax
    add     %rbx, %rdx
91: test    %r8, %r8
    jz      92f
    mov     (%rdx), %r9
    sub     %r9, %rax
    add     %r9, %rdx
    dec     %r8
    jmp     91b
92:
.endm
.endif

/*
 * L0: rax = LANTERN_OK when state rdi has room for the appends of block body rsi, else
 * LANTERN_BUFFER_TOO_SMALL: an eth1 data vote, a validator for each deposit and, in phase0,
 * a PendingAttestation for each attestation in each epoch's list.
 * rbx state, rbp body, r12 the bytes the attestations may add to one list.
 */
LOCAL_FUNCTION block_room
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    FREE    BeaconState_eth1_data_votes, BeaconState_validators, Eth1Data__mem
    cmp     $1, %rax
    jl      9f
    mov     %rbx, %rdi
    call    validator_room
    cmp     (BeaconBlockBody_deposits + 8)(%rbp), %rax
    jb      9f
.if FORK == FORK_PHASE0
    imul    $PENDING_ATTESTATION_ROOM, (BeaconBlockBody_attestations + 8)(%rbp), %r12
    mov     BeaconState_current_epoch_attestations(%rbx), %rcx
    FREE_NESTED BeaconState_previous_epoch_attestations
    cmp     %r12, %rax
    jb      9f
    mov     (%rbx), %rcx
    FREE_NESTED BeaconState_current_epoch_attestations
    cmp     %r12, %rax
    jb      9f
.endif
    xor     %eax, %eax
    LEAVE 0
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
END_FUNCTION block_room
.endif

/*
 * L0: rax = the scratch that lantern_process_block needs for body rsi, with rdx validators.
 * A leaf.
 */
LOCAL_FUNCTION block_scratch
    UNWIND_END_PROLOGUE
    lea     LIST_FIXED(,%rdx,8), %rcx       # L(n)
    imul    $10, %rcx, %rax                 # attestations: S(10) + ATTEST_EXTRA
    add     $(LANTERN_SCRATCH_FIXED + ATTEST_EXTRA), %rax
.if FORK >= FORK_ALTAIR
    lea     (LANTERN_SCRATCH_FIXED + SYNC_AGG_EXTRA)(%rcx), %rdx    # sync aggregate: S(1) + SYNC_AGG_EXTRA
    cmp     %rax, %rdx
    cmova   %rdx, %rax
.endif
.if FORK >= FORK_BELLATRIX
    PART    %r8, %r9, %rsi, BeaconBlockBody_execution_payload     # the payload: its header and transactions
    TX_BYTES %rdx, %r8
    add     $(LANTERN_SCRATCH_FIXED + HEADER_ROOM + 24 + PAYLOAD_WLIST_BYTES), %rdx
    cmp     %rax, %rdx
    cmova   %rdx, %rax
.endif
    ret
END_FUNCTION block_scratch

/* One block step: stop at a failed status or a failed check. */
.macro BLOCK_STEP
    test    %rax, %rax
    jnz     7f
    cmpq    $(0), (%r14)
    jne     8f
.endm

/* Reset scratch r13 to the size in S8. */
.macro SCRATCH_RESET
    mov     S8(%rsp), %rax
    mov     %rax, (%r13)
.endm

/* rbx state, rbp block, r12 config, r13 scratch, r14 result, r15 body, S7 execution_valid, S8 scratch size. */
SPEC_FUNCTION process_block
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, S7(%rsp)
    mov     %rcx, %r12
    mov     %r8, %r13
    mov     %r9, %r14
    PART    %r15, %rax, %rbp, BeaconBlock_body
    mov     %rbx, %rdi
    mov     %r15, %rsi
    call    block_room
    test    %rax, %rax
    jnz     7f
    mov     %r15, %rsi
    mov     (BeaconState_validators + 8)(%rbx), %rdx
    call    block_scratch
    mov     (%r13), %rcx
    mov     %rcx, S8(%rsp)
    cmp     %rax, %rcx
    jb      9f
    movq    $0, (%r14)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    call    lantern_process_block_header
    BLOCK_STEP
.if FORK >= FORK_CAPELLA
    SCRATCH_RESET
    mov     %rbx, %rdi
    PART    %rsi, %rax, %r15, BeaconBlockBody_execution_payload
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    call    lantern_process_withdrawals
    BLOCK_STEP
    SCRATCH_RESET
    mov     %rbx, %rdi
    mov     %r15, %rsi
    mov     S7(%rsp), %rdx
    mov     %r12, %rcx
    mov     %r13, %r8
    mov     %r14, %r9
    call    lantern_process_execution_payload
    BLOCK_STEP
.elseif FORK == FORK_BELLATRIX
    mov     %rbx, %rdi                      # if is_execution_enabled(state, block.body):
    mov     %r15, %rsi
    lea     L(%rsp), %rdx
    call    lantern_is_execution_enabled
    cmpq    $0, L(%rsp)
    je      1f
    SCRATCH_RESET
    mov     %rbx, %rdi
    mov     %r15, %rsi
    mov     S7(%rsp), %rdx
    mov     %r12, %rcx
    mov     %r13, %r8
    mov     %r14, %r9
    call    lantern_process_execution_payload
    BLOCK_STEP
1:
.endif
    SCRATCH_RESET
    mov     %rbx, %rdi
    mov     %r15, %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    call    lantern_process_randao
    BLOCK_STEP
    SCRATCH_RESET
    mov     %rbx, %rdi
    mov     %r15, %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    call    lantern_process_eth1_data
    BLOCK_STEP
    SCRATCH_RESET
    mov     %rbx, %rdi
    mov     %r15, %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    call    lantern_process_operations
    BLOCK_STEP
.if FORK >= FORK_ALTAIR
    SCRATCH_RESET
    mov     %rbx, %rdi
    lea     BeaconBlockBody_sync_aggregate(%r15), %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    call    lantern_process_sync_aggregate
    BLOCK_STEP
.endif
8:  xor     %eax, %eax
7:  LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END process_block

/* ---------------------------------------------------------------- Slots */

/* rbx state, rbp scratch, r12 slot index. Locals: L the state root, L+32 the header root. */
SPEC_FUNCTION process_slot
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     BeaconState_slot(%rbx), %r12
    and     $(SLOTS_PER_HISTORICAL_ROOT - 1), %r12d
    ADDRESS %rdi, lantern_type_BeaconState  # previous_state_root = hash_tree_root(state)
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    lea     L(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    mov     %r12, %rax
    shl     $5, %rax
    lea     BeaconState_state_roots(%rbx,%rax), %rdi
    lea     L(%rsp), %rsi
    COPY32  %rdi, %rsi
    lea     (BeaconState_latest_block_header + BeaconBlockHeader_state_root)(%rbx), %rdi
    mov     (%rdi), %rax
    or      8(%rdi), %rax
    or      16(%rdi), %rax
    or      24(%rdi), %rax
    jnz     1f
    COPY32  %rdi, %rsi                      # the latest header's state root, when it is zero
1:  ADDRESS %rdi, lantern_type_BeaconBlockHeader    # previous_block_root = hash_tree_root(state.latest_block_header)
    lea     BeaconState_latest_block_header(%rbx), %rsi
    mov     %rbp, %rdx
    lea     (L + 32)(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    mov     %r12, %rax
    shl     $5, %rax
    lea     BeaconState_block_roots(%rbx,%rax), %rdi
    lea     (L + 32)(%rsp), %rsi
    COPY32  %rdi, %rsi
    xor     %eax, %eax
7:  LEAVE 64
SPEC_END process_slot

/*
 * L0: rax = LANTERN_OK when state rdi has the room and scratch rdx the bytes to reach slot rsi
 * (a value), plus rcx more scratch bytes; else LANTERN_BUFFER_TOO_SMALL. Also rdx = the epochs
 * crossed. Locals: rsp+0 the slot, rsp+8 scratch, rsp+16 the extra bytes, rsp+24 the validators
 * the epochs may add.
 */
LOCAL_FUNCTION slots_room
    FRAME 32
    mov     %rsi, 0(%rsp)
    mov     %rdx, 8(%rsp)
    mov     %rcx, 16(%rsp)
    mov     BeaconState_slot(%rdi), %r8
    mov     %rsi, %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     %r8, %rcx
    shr     $LOG2_SLOTS_PER_EPOCH, %rcx
    sub     %rcx, %rax                      # epochs crossed
    jae     1f
    xor     %eax, %eax
1:  mov     %rax, %rsi
.if FORK >= FORK_ELECTRA
    mov     $MAX_PENDING_DEPOSITS_PER_EPOCH, %ecx   # room for the validators those epochs may add
    mul     %rcx
    test    %rdx, %rdx
    jnz     9f
    mov     %rax, 24(%rsp)
    mov     $-1, %r9
    VALIDATOR_LISTS LIST_ROOM
    cmp     24(%rsp), %r9
    jb      9f
.else
    movq    $0, 24(%rsp)                    # epochs add no validators
.endif
.if FORK == FORK_PHASE0
    test    %rsi, %rsi                      # the current epoch's attestations move to the previous list once
    jz      4f
    mov     BeaconState_current_epoch_attestations(%rdi), %rcx
    mov     (BeaconState_current_epoch_attestations + 8)(%rdi), %rdx
    lea     (%rdi,%rcx), %r9
    xor     %eax, %eax
3:  test    %rdx, %rdx
    jz      31f
    add     (%r9), %rax
    add     (%r9), %r9
    dec     %rdx
    jmp     3b
31: sub     BeaconState_previous_epoch_attestations(%rdi), %rcx
    cmp     %rcx, %rax
    ja      9f
4:
.endif
    mov     0(%rsp), %rax                   # and for a historical root or summary per batch boundary
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    xor     %edx, %edx
    mov     $(SLOTS_PER_HISTORICAL_ROOT / SLOTS_PER_EPOCH), %ecx
    div     %rcx
    mov     %rax, %r9
    mov     %r8, %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    xor     %edx, %edx
    div     %rcx
    sub     %rax, %r9
    jae     2f
    xor     %r9d, %r9d
2:
.if FORK >= FORK_CAPELLA
.if FORK >= FORK_ELECTRA
    mov     BeaconState_pending_deposits(%rdi), %rax
.else
    mov     (%rdi), %rax                    # the last part ends at the end of the value
.endif
    sub     BeaconState_historical_summaries(%rdi), %rax
    shr     $6, %rax
    sub     (BeaconState_historical_summaries + 8)(%rdi), %rax
.else
    mov     BeaconState_eth1_data_votes(%rdi), %rax
    sub     BeaconState_historical_roots(%rdi), %rax
    shr     $5, %rax
    sub     (BeaconState_historical_roots + 8)(%rdi), %rax
.endif
    cmp     %r9, %rax
    jb      9f
    mov     (BeaconState_validators + 8)(%rdi), %rax    # scratch: process_epoch with every validator the epochs may add
    add     24(%rsp), %rax
    lea     LIST_FIXED(,%rax,8), %rax
    imul    $EPOCH_LISTS, %rax, %rax
    add     $(LANTERN_SCRATCH_FIXED + EPOCH_EXTRA), %rax
    mov     16(%rsp), %rcx
    cmp     %rax, %rcx
    cmova   %rcx, %rax
    mov     8(%rsp), %rcx
    cmp     %rax, (%rcx)
    jb      9f
    mov     %rsi, %rdx
    xor     %eax, %eax
    UNFRAME 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    UNFRAME 32
END_FUNCTION slots_room

/* rbx state, rbp slot, r12 config, r13 scratch, r14 result, r15 scratch size. */
SPEC_FUNCTION process_slots
    ENTER 16
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    movq    $0, (%r14)
    cmp     BeaconState_slot(%rbx), %rbp    # assert state.slot < slot
    ja      1f
    movq    $LANTERN_INVALID_SLOT, (%r14)
    jmp     8f
1:  mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r13, %rdx
    xor     %ecx, %ecx
    call    slots_room
    test    %rax, %rax
    jnz     7f
    mov     (%r13), %r15
2:  cmp     BeaconState_slot(%rbx), %rbp
    jbe     8f
    mov     %r15, (%r13)
    mov     %rbx, %rdi
    mov     %r13, %rsi
    call    lantern_process_slot
    test    %rax, %rax
    jnz     7f
    mov     BeaconState_slot(%rbx), %rax
    inc     %rax
    test    $(SLOTS_PER_EPOCH - 1), %rax
    jnz     3f
    mov     %r15, (%r13)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     %r13, %rdx
    mov     %r14, %rcx
    call    lantern_process_epoch
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (%r14)
    jne     8f
3:  incq    BeaconState_slot(%rbx)
    jmp     2b
8:  xor     %eax, %eax
7:  LEAVE 16
SPEC_END process_slots

/* ---------------------------------------------------------------- Blocks and the transition */

/*
 * rbx state, rbp signed block, r12 scratch, r13 out, r14 block, r15 proposer.
 * Locals: L epoch, L+8 domain type, L+16 domain (32), L+48 signing root as a ByteList (56).
 */
SPEC_FUNCTION verify_block_signature
    ENTER 112
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    movq    $0, (%r13)
    PART    %r14, %rax, %rbp, SignedBeaconBlock_message
    mov     BeaconBlock_proposer_index(%r14), %rcx
    cmp     (BeaconState_validators + 8)(%rbx), %rcx
    jae     6f
    VALIDATOR %r15, %rbx, %rcx
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    movl    $DOMAIN_BEACON_PROPOSER, (L + 8)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    lea     L(%rsp), %rdx
    mov     %r12, %rcx
    lea     (L + 16)(%rsp), %r8
    call    lantern_get_domain
    test    %rax, %rax
    jnz     7f
    ADDRESS %rdi, lantern_type_BeaconBlock
    mov     %r14, %rsi
    lea     (L + 16)(%rsp), %rdx
    mov     %r12, %rcx
    lea     (L + 72)(%rsp), %r8
    call    lantern_compute_signing_root
    test    %rax, %rax
    jnz     7f
    lea     Validator_pubkey(%r15), %rdi
    lea     SignedBeaconBlock_signature(%rbp), %rsi
    lea     (L + 48)(%rsp), %rdx
    mov     %r12, %rcx
    call    verify_root_signature
    test    %rax, %rax
    jnz     7f
    mov     %rdx, (%r13)
7:  LEAVE 112
6:  mov     $LANTERN_INVALID_VALIDATOR_INDEX, %eax
    LEAVE 112
SPEC_END verify_block_signature

/*
 * rbx state, rbp signed block, r12 options, r13 config, r14 scratch, r15 result,
 * S7 block, S8 scratch size. Locals: L valid, L+8 state root (32).
 */
SPEC_FUNCTION state_transition
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r9, %r15
    movq    $0, (%r15)
    PART    %rax, %rcx, %rbp, SignedBeaconBlock_message
    mov     %rax, S7(%rsp)
    mov     (%r14), %rcx
    mov     %rcx, S8(%rsp)
    PART    %rsi, %rcx, %rax, BeaconBlock_body  # before any change: room and scratch for the slots and the block
    mov     %rbx, %rdi
    call    block_room
    test    %rax, %rax
    jnz     7f
    mov     %rbx, %rdi                      # the epochs the slots cross
    mov     S7(%rsp), %rax
    mov     BeaconBlock_slot(%rax), %rsi
    mov     %r14, %rdx
    xor     %ecx, %ecx
    call    slots_room
    test    %rax, %rax
    jnz     7f
    imul    $MAX_PENDING_DEPOSITS_PER_EPOCH, %rdx, %rdx # the block's scratch, with every validator they may add
    add     (BeaconState_validators + 8)(%rbx), %rdx
    mov     S7(%rsp), %rax
    PART    %rsi, %rcx, %rax, BeaconBlock_body
    call    block_scratch
    cmp     %rax, (%r14)
    jb      9f
    mov     %rbx, %rdi                      # process_slots(state, block.slot)
    mov     S7(%rsp), %rsi
    add     $BeaconBlock_slot, %rsi
    mov     %r13, %rdx
    mov     %r14, %rcx
    mov     %r15, %r8
    call    lantern_process_slots
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (%r15)
    jne     8f
    cmpq    $0, (%r12)                      # if validate_result: assert verify_block_signature(state, signed_block)
    je      1f
    mov     S8(%rsp), %rax
    mov     %rax, (%r14)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r14, %rdx
    lea     L(%rsp), %rcx
    call    lantern_verify_block_signature
    CHECK_STATUS %r15, 7f, 8f
    cmpq    $0, L(%rsp)
    jne     1f
    movq    $LANTERN_INVALID_BLOCK_SIGNATURE, (%r15)
    jmp     8f
1:  mov     S8(%rsp), %rax
    mov     %rax, (%r14)
    mov     %rbx, %rdi                      # process_block(state, block)
    mov     S7(%rsp), %rsi
    lea     8(%r12), %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    mov     %r15, %r9
    call    lantern_process_block
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (%r15)
    jne     8f
    cmpq    $0, (%r12)                      # if validate_result: assert block.state_root == hash_tree_root(state)
    je      8f
    mov     S8(%rsp), %rax
    mov     %rax, (%r14)
    ADDRESS %rdi, lantern_type_BeaconState
    mov     %rbx, %rsi
    mov     %r14, %rdx
    lea     (L + 8)(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    mov     S7(%rsp), %rax
    lea     BeaconBlock_state_root(%rax), %rcx
    lea     (L + 8)(%rsp), %rdx
    NE32    %rcx, %rdx, 2f
    jmp     8f
2:  movq    $LANTERN_INVALID_STATE_ROOT, (%r15)
8:  xor     %eax, %eax
7:  LEAVE 48
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
SPEC_END state_transition
