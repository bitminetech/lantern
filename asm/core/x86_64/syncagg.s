/*
 * The sync aggregate, x86-64. Requirements: docs/reference/block-processing.md.
 */

.set G1_POINT_BYTES, 144                                        /* asm-crypto G1Point: X, Y, Z */
.set SYNC_KEYS_LIST, 24 + 48 * SYNC_COMMITTEE_SIZE              /* a BlsPublicKeyList of the committee */
.set SYNC_AGG_EXTRA, SYNC_KEYS_LIST + SYNC_INDICES_BYTES + 3 * G1_POINT_BYTES + 48

/* Append the 48-byte key at register key to the BlsPublicKeyList at register list. Uses r8, r9, xmm0-xmm2. */
.macro KEYS_APPEND list, key
    mov     16(\list), %r8
    lea     1(%r8), %r9
    mov     %r9, 16(\list)
    imul    $48, %r8, %r8
    lea     24(\list,%r8), %r8
    movdqu  (\key), %xmm0
    movdqu  16(\key), %xmm1
    movdqu  32(\key), %xmm2
    movdqu  %xmm0, (%r8)
    movdqu  %xmm1, 16(%r8)
    movdqu  %xmm2, 32(%r8)
.endm

/* rcx = the address of current_sync_committee.pubkeys[r14] of state rbx. */
.macro SYNC_KEY
    imul    $(48), %r14, %rcx
    lea     (BeaconState_current_sync_committee + SyncCommittee_pubkeys)(%rbx,%rcx), %rcx
.endm

/*
 * rbx state, rbp sync aggregate, r12 scratch, r13 result, r14 i, r15 keys,
 * S7 committee indices, S8 the non participant aggregate then the committee entries, S9 scratch size, S10 P1.
 * Locals: L SYNC_COMMITTEE_SIZE, L+8 previous slot, L+16 epoch, L+24 domain type, L+32 domain (32),
 * L+64 signing root as a ByteList (56), L+120 block root (32), L+152 valid or bit count, L+160 total active balance,
 * L+168 base reward per increment, L+176 participant reward, L+184 proposer reward, L+192 proposer, L+200 the one.
 */
FUNCTION lantern_process_sync_aggregate
    ENTER 208
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rcx, %r12
    mov     %r8, %r13
    NEED_SCRATCH_B %r12, %rbx, 1, SYNC_AGG_EXTRA, 9f
    movq    $0, (%r13)
    mov     (%r12), %rax
    mov     %rax, S9(%rsp)
    sub     $SYNC_KEYS_LIST, %rax           # own scratch at the end: keys, committee indices, points
    lea     (%r12,%rax), %r15
    movq    $SYNC_KEYS_LIST, (%r15)
    movq    $24, 8(%r15)
    movq    $0, 16(%r15)
    sub     $SYNC_INDICES_BYTES, %rax
    lea     (%r12,%rax), %rcx
    movq    $SYNC_INDICES_BYTES, (%rcx)
    mov     %rcx, S7(%rsp)
    mov     S9(%rsp), %rax
    sub     $SYNC_AGG_EXTRA, %rax
    mov     %rax, (%r12)                    # what callees get
    movq    $SYNC_COMMITTEE_SIZE, L(%rsp)
    lea     SyncAggregate_sync_committee_bits(%rbp), %rdi
    lea     L(%rsp), %rsi
    lea     (L + 152)(%rsp), %rdx
    call    lantern_get_set_bit_count
    mov     (L + 152)(%rsp), %rax
    cmp     $SYNC_COMMITTEE_SIZE, %rax
    jne     1f
    lea     (BeaconState_current_sync_committee + SyncCommittee_aggregate_pubkey)(%rbx), %rcx  # all signed: [aggregate_pubkey]
    KEYS_APPEND %r15, %rcx
    jmp     4f
1:  cmp     $(SYNC_COMMITTEE_SIZE / 2), %rax
    jbe     3f
    xor     %r14d, %r14d                    # more than half: aggregate minus the non participants
2:  cmp     $SYNC_COMMITTEE_SIZE, %r14
    jae     25f
    bt      %r14, SyncAggregate_sync_committee_bits(%rbp)
    jc      21f
    SYNC_KEY
    KEYS_APPEND %r15, %rcx
21: inc     %r14
    jmp     2b
25: mov     S9(%rsp), %rax                  # points: P1, P2, P3; then the non participant aggregate
    sub     $SYNC_AGG_EXTRA, %rax
    add     %r12, %rax
    mov     %rax, S10(%rsp)                 # P1
    mov     S9(%rsp), %rax
    sub     $(SYNC_KEYS_LIST + SYNC_INDICES_BYTES + 48), %rax
    add     %r12, %rax
    mov     %rax, S8(%rsp)                  # the non participant aggregate, 48 bytes
    mov     %r15, %rdi
    mov     %rax, %rsi
    CALL_GLOBAL crypto_bls_eth_aggregate_pubkeys
    test    %rax, %rax
    jnz     5f
    lea     (BeaconState_current_sync_committee + SyncCommittee_aggregate_pubkey)(%rbx), %rdi  # bls.bytes48_to_G1(aggregate_pubkey)
    mov     S10(%rsp), %rsi
    CALL_GLOBAL crypto_bls_g1_decode
    test    %rax, %rax
    jnz     5f
    mov     S8(%rsp), %rdi                  # bls.bytes48_to_G1(non_participant_aggregate)
    mov     S10(%rsp), %rsi
    add     $G1_POINT_BYTES, %rsi
    CALL_GLOBAL crypto_bls_g1_decode
    test    %rax, %rax
    jnz     5f
    mov     S10(%rsp), %rdi                 # bls.neg(...)
    lea     (2 * G1_POINT_BYTES)(%rdi), %rsi
    add     $G1_POINT_BYTES, %rdi
    CALL_GLOBAL crypto_bls_g1_neg
    mov     S10(%rsp), %rdi                 # bls.add(...)
    lea     (2 * G1_POINT_BYTES)(%rdi), %rsi
    lea     G1_POINT_BYTES(%rdi), %rdx
    CALL_GLOBAL crypto_bls_g1_add
    mov     S10(%rsp), %rdi                 # participant_pubkeys = [G1_to_bytes48(...)]
    add     $G1_POINT_BYTES, %rdi
    mov     S8(%rsp), %rsi
    CALL_GLOBAL crypto_bls_g1_compress
    movq    $0, 16(%r15)
    mov     S8(%rsp), %rcx
    KEYS_APPEND %r15, %rcx
    jmp     4f
3:  xor     %r14d, %r14d                    # at most half: the participants
31: cmp     $SYNC_COMMITTEE_SIZE, %r14
    jae     4f
    bt      %r14, SyncAggregate_sync_committee_bits(%rbp)
    jnc     32f
    SYNC_KEY
    KEYS_APPEND %r15, %rcx
32: inc     %r14
    jmp     31b
4:  movq    $1, (L + 200)(%rsp)             # previous_slot = saturating_sub(state.slot, 1)
    lea     BeaconState_slot(%rbx), %rdi
    lea     (L + 200)(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_saturating_sub
    mov     (L + 8)(%rsp), %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     %rax, (L + 16)(%rsp)
    movl    $DOMAIN_SYNC_COMMITTEE, (L + 24)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 24)(%rsp), %rsi
    lea     (L + 16)(%rsp), %rdx
    mov     %r12, %rcx
    lea     (L + 32)(%rsp), %r8
    call    lantern_get_domain
    test    %rax, %rax
    jnz     7f
    mov     %rbx, %rdi                      # get_block_root_at_slot(state, previous_slot)
    lea     (L + 8)(%rsp), %rsi
    lea     (L + 120)(%rsp), %rdx
    call    lantern_get_block_root_at_slot
    CHECK_STATUS %r13, 7f, 8f
    ADDRESS %rdi, lantern_type_Bytes32
    lea     (L + 120)(%rsp), %rsi
    lea     (L + 32)(%rsp), %rdx
    mov     %r12, %rcx
    lea     (L + 88)(%rsp), %r8
    call    lantern_compute_signing_root
    test    %rax, %rax
    jnz     7f
    movq    $56, (L + 64)(%rsp)
    movq    $24, (L + 72)(%rsp)
    movq    $32, (L + 80)(%rsp)
    mov     %r15, %rdi                      # assert eth_fast_aggregate_verify(participant_pubkeys, signing_root, signature)
    lea     (L + 64)(%rsp), %rsi
    lea     SyncAggregate_sync_committee_signature(%rbp), %rdx
    mov     %r12, %rcx
    lea     (L + 152)(%rsp), %r8
    CALL_GLOBAL crypto_bls_eth_fast_aggregate_verify
    test    %rax, %rax
    jnz     7f
    mov     $LANTERN_INVALID_SYNC_AGGREGATE, %eax
    cmpq    $0, (L + 152)(%rsp)
    je      6f
    xor     %r14d, %r14d                    # committee_indices = [all_pubkeys.index(pubkey) for pubkey in committee]
    mov     S7(%rsp), %rax
    add     $LIST_FIXED, %rax
    mov     %rax, S8(%rsp)
41: cmp     $SYNC_COMMITTEE_SIZE, %r14
    jae     42f
    SYNC_KEY
    mov     %rcx, %rsi
    mov     %rbx, %rdi
    call    find_pubkey
    mov     %rax, %rcx
    mov     $LANTERN_INVALID_SYNC_AGGREGATE, %eax
    cmp     $-1, %rcx
    je      6f
    mov     S8(%rsp), %rdx
    mov     %rcx, (%rdx,%r14,8)
    inc     %r14
    jmp     41b
42: mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     (L + 160)(%rsp), %rdx
    call    lantern_get_total_active_balance
    test    %rax, %rax
    jnz     7f
    mov     S9(%rsp), %rax
    sub     $SYNC_AGG_EXTRA, %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     (L + 168)(%rsp), %rdx
    call    lantern_get_base_reward_per_increment
    test    %rax, %rax
    jnz     7f
    mov     (L + 160)(%rsp), %rax
    MOVQ    %rcx, EFFECTIVE_BALANCE_INCREMENT
    xor     %edx, %edx
    div     %rcx                            # total_active_increments
    imul    (L + 168)(%rsp), %rax           # total_base_rewards
    imul    $SYNC_REWARD_WEIGHT, %rax, %rax
    shr     $6, %rax                        # // WEIGHT_DENOMINATOR
    shr     $LOG2_SLOTS_PER_EPOCH, %rax     # max_participant_rewards
    mov     $SYNC_COMMITTEE_SIZE, %ecx
    xor     %edx, %edx
    div     %rcx                            # participant_reward
    mov     %rax, (L + 176)(%rsp)
    imul    $PROPOSER_WEIGHT, %rax, %rax
    mov     $(WEIGHT_DENOMINATOR - PROPOSER_WEIGHT), %ecx
    xor     %edx, %edx
    div     %rcx
    mov     %rax, (L + 184)(%rsp)
    xor     %r14d, %r14d
43: cmp     $SYNC_COMMITTEE_SIZE, %r14
    jae     8f
    mov     S8(%rsp), %rsi
    lea     (%rsi,%r14,8), %rsi
    bt      %r14, SyncAggregate_sync_committee_bits(%rbp)
    jnc     44f
    mov     %rbx, %rdi                      # increase_balance(state, participant_index, participant_reward)
    lea     (L + 176)(%rsp), %rdx
    call    lantern_increase_balance
    mov     %rbx, %rdi
    lea     (L + 192)(%rsp), %rsi
    call    lantern_get_beacon_proposer_index
    mov     %rbx, %rdi                      # increase_balance(state, proposer, proposer_reward)
    lea     (L + 192)(%rsp), %rsi
    lea     (L + 184)(%rsp), %rdx
    call    lantern_increase_balance
    jmp     45f
44: mov     %rbx, %rdi                      # decrease_balance(state, participant_index, participant_reward)
    lea     (L + 176)(%rsp), %rdx
    call    lantern_decrease_balance
45: inc     %r14
    jmp     43b
8:  xor     %eax, %eax
7:  LEAVE 208
5:  mov     $LANTERN_INVALID_AGGREGATE_PUBKEYS, %eax
6:  mov     %rax, (%r13)
    xor     %eax, %eax
    LEAVE 208
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 208
END_FUNCTION lantern_process_sync_aggregate

.if WEIGHT_DENOMINATOR != 64
.error "lantern_process_sync_aggregate divides by WEIGHT_DENOMINATOR with a shift by 6"
.endif
