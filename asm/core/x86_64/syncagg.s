/*
 * The sync aggregate, x86-64. Requirements: docs/reference/block-processing.md.
 */

.set G1_POINT_BYTES, 144                                        /* asm-crypto G1Point: X, Y, Z */
.set SYNC_KEYS_LIST, 24 + 48 * SYNC_COMMITTEE_SIZE              /* a BlsPublicKeyList of the committee */
.set SYNC_AGG_EXTRA, SYNC_KEYS_LIST + SYNC_INDICES_BYTES + 3 * G1_POINT_BYTES + 48
.set SYNC_TABLE_SLOTS, 2 * SYNC_COMMITTEE_SIZE                  /* lantern_find_pubkeys: slots of (fingerprint, member + 1) */
.set SYNC_TABLE_BYTES, 16 * SYNC_TABLE_SLOTS
.if SYNC_TABLE_SLOTS & (SYNC_TABLE_SLOTS - 1)
.error "find_pubkeys takes a slot number by a mask: SYNC_COMMITTEE_SIZE must be a power of 2"
.endif
.if SYNC_TABLE_BYTES + 24 > SYNC_KEYS_LIST
.error "the hash table of find_pubkeys and its 3 words do not fit where the keys were"
.endif

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
 * L+168 base reward per increment, L+176 participant reward, L+184 proposer reward, L+192 proposer, L+200 the one,
 * L+208 1 when r15 is the participants' indices for crypto_bls_fast_aggregate_verify_cached, else 0, L+216 config.
 */
SPEC_FUNCTION process_sync_aggregate
    ENTER 224
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, (L + 216)(%rsp)          # config
    mov     %rcx, %r12
    mov     %r8, %r13
.if FORK >= FORK_FULU
    NEED_SCRATCH_B %r12, %rbx, 1, SYNC_AGG_EXTRA, 9f
.else
    NEED_SCRATCH_B %r12, %rbx, 2, SYNC_AGG_EXTRA, 9f    # get_beacon_proposer_index takes S(2)
.endif
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
    movq    $0, (L + 208)(%rsp)
    cmp     $SYNC_COMMITTEE_SIZE, %rax
    jne     1f
    lea     (BeaconState_current_sync_committee + SyncCommittee_aggregate_pubkey)(%rbx), %rcx  # all signed: [aggregate_pubkey]
    KEYS_APPEND %r15, %rcx
    jmp     4f
1:  mov     (L + 216)(%rsp), %rcx           # with a key cache, some signed: one cached check of their indices
    mov     CONFIG_PUBKEY_CACHE(%rcx), %rcx
    test    %rcx, %rcx
    jz      11f
    test    %rax, %rax
    jz      11f
    mov     %rbx, %rdi                      # committee_indices first: the participants' keys are those validators'
    lea     (BeaconState_current_sync_committee + SyncCommittee_pubkeys)(%rbx), %rsi
    mov     S7(%rsp), %rdx
    add     $LIST_FIXED, %rdx
    mov     %r15, %rcx                      # the hash table, where the keys go
    call    lantern_find_pubkeys
    mov     %rax, %rcx
    mov     $LANTERN_INVALID_SYNC_AGGREGATE, %eax
    test    %rcx, %rcx
    jnz     6f
    movq    $SYNC_KEYS_LIST, (%r15)         # the participants' indices: a BlsIndexList where the keys were
    movq    $24, 8(%r15)
    mov     (L + 216)(%rsp), %rcx
    mov     CONFIG_PUBKEY_CACHE(%rcx), %rcx
    mov     CRYPTO_BLS_CACHE_COUNT(%rcx), %r8
    mov     S7(%rsp), %r9
    add     $LIST_FIXED, %r9
    xor     %r14d, %r14d
    xor     %r10d, %r10d
12: cmp     $SYNC_COMMITTEE_SIZE, %r14
    jae     13f
    bt      %r14, SyncAggregate_sync_committee_bits(%rbp)
    jnc     121f
    mov     (%r9,%r14,8), %rax
    cmp     %r8, %rax
    jae     14f                             # an index past the cache: the spec's steps
    mov     %rax, 24(%r15,%r10,8)
    inc     %r10
121: inc    %r14
    jmp     12b
13: mov     %r10, 16(%r15)
    movq    $1, (L + 208)(%rsp)
    jmp     4f
14: movq    $0, 16(%r15)
11: mov     (L + 152)(%rsp), %rax
    cmp     $(SYNC_COMMITTEE_SIZE / 2), %rax
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
    cmpq    $0, (L + 208)(%rsp)
    jne     46f
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
    mov     S7(%rsp), %rdx                  # committee_indices = [all_pubkeys.index(pubkey) for pubkey in committee]
    add     $LIST_FIXED, %rdx
    mov     %rdx, S8(%rsp)
    mov     %rbx, %rdi
    lea     (BeaconState_current_sync_committee + SyncCommittee_pubkeys)(%rbx), %rsi
    mov     %r15, %rcx                      # the hash table, where the keys were
    call    lantern_find_pubkeys
    mov     %rax, %rcx
    mov     $LANTERN_INVALID_SYNC_AGGREGATE, %eax
    test    %rcx, %rcx
    jnz     6f
47: mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     (L + 160)(%rsp), %rdx
    call    lantern_get_total_active_balance
    test    %rax, %rax
    jnz     7f
    mov     S9(%rsp), %rax
    sub     $SYNC_AGG_EXTRA, %rax
    mov     %rax, (%r12)
    lea     (L + 160)(%rsp), %rdi           # get_base_reward_per_increment of the same total
    lea     (L + 168)(%rsp), %rsi
    call    lantern_integer_squareroot
    MOVQ    %rax, EFFECTIVE_BALANCE_INCREMENT * BASE_REWARD_FACTOR
    xor     %edx, %edx
    divq    (L + 168)(%rsp)
    mov     %rax, (L + 168)(%rsp)
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
    mov     %rbx, %rdi                      # get_beacon_proposer_index(state): the loop changes only balances
.if FORK >= FORK_FULU
    lea     (L + 192)(%rsp), %rsi
.else
    mov     S9(%rsp), %rax
    sub     $SYNC_AGG_EXTRA, %rax
    mov     %rax, (%r12)
    mov     %r12, %rsi
    lea     (L + 192)(%rsp), %rdx
.endif
    call    lantern_get_beacon_proposer_index
    test    %rax, %rax
    jnz     7f
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
7:  LEAVE 224
5:  mov     $LANTERN_INVALID_AGGREGATE_PUBKEYS, %eax
6:  mov     %rax, (%r13)
    xor     %eax, %eax
    LEAVE 224
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 224
46: mov     S7(%rsp), %rdx                  # eth_fast_aggregate_verify of at least one key, through the cache
    add     $LIST_FIXED, %rdx
    mov     %rdx, S8(%rsp)                  # committee_indices, found before
    mov     BeaconState_validators(%rbx), %rdi
    add     %rbx, %rdi
    add     $Validator_pubkey, %rdi
    mov     %r15, %rsi
    mov     (L + 216)(%rsp), %rdx
    mov     CONFIG_PUBKEY_CACHE(%rdx), %rdx
    lea     (L + 64)(%rsp), %rcx
    lea     SyncAggregate_sync_committee_signature(%rbp), %r8
    mov     %r12, %r9
    lea     (L + 152)(%rsp), %rax
    mov     %rax, S7(%rsp)                  # valid: the 7th argument, at the stack pointer
    CALL_GLOBAL crypto_bls_fast_aggregate_verify_cached
    test    %rax, %rax
    jnz     7b
    mov     $LANTERN_INVALID_SYNC_AGGREGATE, %eax
    cmpq    $0, (L + 152)(%rsp)
    je      6b
    jmp     47b
SPEC_END process_sync_aggregate

.if WEIGHT_DENOMINATOR != 64
.error "lantern_process_sync_aggregate divides by WEIGHT_DENOMINATOR with a shift by 6"
.endif

/*
 * all_pubkeys.index(pubkey) of state rdi for each of the SYNC_COMMITTEE_SIZE 48-byte keys at
 * rsi, written to the u64 entries at rdx: the first validator with the key. One pass over the
 * validators, with the distinct keys in a hash table at rcx (SYNC_TABLE_BYTES): a slot holds the
 * key's bytes 8 to 15, then its member + 1, or 0 when empty. After the table: the validator count,
 * the distinct keys not found yet, the state. While the pass runs, an entry holds -1 for a key not
 * found yet, or 1 << 63 | j for a key that is that of member j < k.
 * rax = 0, or -1 when a key is missing. Uses rdi, r8-r11, xmm0-xmm5.
 */
LOCAL_FUNCTION lantern_find_pubkeys
    UNWIND_END_PROLOGUE
    mov     %rdi, (SYNC_TABLE_BYTES + 16)(%rcx)
    pxor    %xmm0, %xmm0                    # the table: empty
    xor     %eax, %eax
1:  movdqu  %xmm0, (%rcx,%rax)
    add     $16, %rax
    cmp     $SYNC_TABLE_BYTES, %rax
    jb      1b
    movq    $0, (SYNC_TABLE_BYTES + 8)(%rcx)
    xor     %r8d, %r8d                      # k
2:  cmp     $SYNC_COMMITTEE_SIZE, %r8
    jae     6f
    imul    $48, %r8, %r9
    add     %rsi, %r9                       # key k
    mov     8(%r9), %r10                    # its fingerprint
    mov     %r10d, %eax
    and     $(SYNC_TABLE_SLOTS - 1), %eax
3:  mov     %rax, %r11
    shl     $4, %r11
    add     %rcx, %r11                      # the slot
    cmpq    $0, 8(%r11)
    je      5f
    cmp     (%r11), %r10
    jne     4f
    mov     8(%r11), %rdi                   # the same fingerprint: the key of member j
    dec     %rdi
    imul    $48, %rdi, %rdi
    add     %rsi, %rdi
    movdqu  (%r9), %xmm0
    movdqu  16(%r9), %xmm1
    movdqu  32(%r9), %xmm2
    movdqu  (%rdi), %xmm3
    movdqu  16(%rdi), %xmm4
    movdqu  32(%rdi), %xmm5
    pcmpeqb %xmm3, %xmm0
    pcmpeqb %xmm4, %xmm1
    pcmpeqb %xmm5, %xmm2
    pand    %xmm1, %xmm0
    pand    %xmm2, %xmm0
    pmovmskb %xmm0, %edi
    cmp     $0xffff, %edi
    jne     4f
    mov     8(%r11), %rdi                   # the key of member j: 1 << 63 | j
    dec     %rdi
    bts     $63, %rdi
    mov     %rdi, (%rdx,%r8,8)
    jmp     55f
4:  inc     %eax
    and     $(SYNC_TABLE_SLOTS - 1), %eax
    jmp     3b
5:  mov     %r10, (%r11)                    # a new key
    lea     1(%r8), %rdi
    mov     %rdi, 8(%r11)
    movq    $-1, (%rdx,%r8,8)
    incq    (SYNC_TABLE_BYTES + 8)(%rcx)
55: inc     %r8
    jmp     2b
6:  mov     (SYNC_TABLE_BYTES + 16)(%rcx), %rdi
    PART    %r9, %r10, %rdi, BeaconState_validators
    mov     %r10, SYNC_TABLE_BYTES(%rcx)
    mov     %r9, %rdi                       # validator i
    xor     %r8d, %r8d                      # i
7:  cmp     SYNC_TABLE_BYTES(%rcx), %r8
    jae     10f
    mov     (Validator_pubkey + 8)(%rdi), %r10
    mov     %r10d, %eax
    and     $(SYNC_TABLE_SLOTS - 1), %eax
8:  mov     %rax, %r11
    shl     $4, %r11
    mov     8(%rcx,%r11), %r9
    test    %r9, %r9
    jz      95f
    cmp     (%rcx,%r11), %r10
    jne     9f
    lea     -1(%r9), %r11                   # the same fingerprint: compare the whole key
    imul    $48, %r11, %r11
    add     %rsi, %r11
    movdqu  Validator_pubkey(%rdi), %xmm0
    movdqu  (Validator_pubkey + 16)(%rdi), %xmm1
    movdqu  (Validator_pubkey + 32)(%rdi), %xmm2
    movdqu  (%r11), %xmm3
    movdqu  16(%r11), %xmm4
    movdqu  32(%r11), %xmm5
    pcmpeqb %xmm3, %xmm0
    pcmpeqb %xmm4, %xmm1
    pcmpeqb %xmm5, %xmm2
    pand    %xmm1, %xmm0
    pand    %xmm2, %xmm0
    pmovmskb %xmm0, %r11d
    cmp     $0xffff, %r11d
    jne     9f
    dec     %r9                             # the first validator with the key: its index
    cmpq    $-1, (%rdx,%r9,8)
    jne     95f
    mov     %r8, (%rdx,%r9,8)
    decq    (SYNC_TABLE_BYTES + 8)(%rcx)
    jz      10f
    jmp     95f
9:  inc     %eax
    and     $(SYNC_TABLE_SLOTS - 1), %eax
    jmp     8b
95: add     $Validator__mem, %rdi
    inc     %r8
    jmp     7b
10: xor     %r8d, %r8d                      # each repeated key takes the index of its first member
11: cmp     $SYNC_COMMITTEE_SIZE, %r8
    jae     13f
    mov     (%rdx,%r8,8), %rax
    cmp     $-1, %rax
    je      12f
    btr     $63, %rax
    jnc     115f
    mov     (%rdx,%rax,8), %rax
    cmp     $-1, %rax
    je      12f
    mov     %rax, (%rdx,%r8,8)
115: inc    %r8
    jmp     11b
12: mov     $-1, %rax
    ret
13: xor     %eax, %eax
    ret
END_FUNCTION lantern_find_pubkeys
