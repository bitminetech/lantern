/*
 * Genesis, x86-64. Requirements: docs/reference/genesis.md.
 */

.if FORK == FORK_PHASE0

.set MERKLE_DEPTH, 40                                   /* the deepest list: VALIDATOR_REGISTRY_LIMIT entries */
.if ((1 << MERKLE_DEPTH) != VALIDATOR_REGISTRY_LIMIT) || (DEPOSIT_CONTRACT_TREE_DEPTH > MERKLE_DEPTH)
.error "genesis: a list limit is not one that the Merkle trees take"
.endif
.set TREE_BYTES, 8 + 32 * MERKLE_DEPTH                  /* a tree: its leaf count, then a branch node for each level */
.set ZEROS_BYTES, 32 * MERKLE_DEPTH                     /* the zero hashes of levels 0 to MERKLE_DEPTH - 1 */
.set BODY_BYTES, (BeaconBlockBody__fixed + 7) / 8 * 8   /* BeaconBlockBody() */
.set GENESIS_EXTRA, TREE_BYTES + ZEROS_BYTES + BODY_BYTES

/* Append the 32-byte leaf rsi to tree rdi, as the deposit contract does. rbx tree, rbp size, r12 level. Locals: L a pair (64). */
LOCAL_FUNCTION merkle_add
    ENTER 64
    mov     %rdi, %rbx
    lea     (L + 32)(%rsp), %rax            # node = leaf, in the pair's right half
    COPY32  %rax, %rsi
    mov     (%rbx), %rbp
    inc     %rbp
    mov     %rbp, (%rbx)
    xor     %r12d, %r12d
1:  test    $1, %rbp                        # an odd size: the node is the branch of this level
    jnz     2f
    mov     %r12, %rax                      # node = hash(branch[level] + node)
    shl     $5, %rax
    lea     8(%rbx,%rax), %rax
    lea     L(%rsp), %rcx
    COPY32  %rcx, %rax
    lea     L(%rsp), %rdi
    mov     $64, %esi
    lea     (L + 32)(%rsp), %rdx
    call    sha256_short
    shr     $1, %rbp
    inc     %r12
    cmp     $MERKLE_DEPTH, %r12
    jb      1b
    jmp     3f
2:  mov     %r12, %rax
    shl     $5, %rax
    lea     8(%rbx,%rax), %rax
    lea     (L + 32)(%rsp), %rcx
    COPY32  %rax, %rcx
3:  LEAVE 64
END_FUNCTION merkle_add

/*
 * The root of tree rdi as a list of depth rdx levels, its length mixed in, at rcx; rsi holds the zero hashes.
 * rbx tree, rbp zeros, r12 depth, r13 out, r14 size, r15 level. Locals: L a pair (64).
 */
LOCAL_FUNCTION merkle_root
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     (%rbx), %r14
    lea     (L + 32)(%rsp), %rdi            # node = zero, in the pair's right half
    mov     $32, %esi
    call    lantern_zero
    xor     %r15d, %r15d
1:  cmp     %r12, %r15
    jae     4f
    test    $1, %r14
    jz      2f
    mov     %r15, %rax                      # odd: hash(branch[level] + node)
    shl     $5, %rax
    lea     8(%rbx,%rax), %rax
    lea     L(%rsp), %rcx
    COPY32  %rcx, %rax
    jmp     3f
2:  lea     L(%rsp), %rcx                   # even: hash(node + zero_hashes[level])
    lea     (L + 32)(%rsp), %rax
    COPY32  %rcx, %rax
    mov     %r15, %rax
    shl     $5, %rax
    add     %rbp, %rax
    lea     (L + 32)(%rsp), %rcx
    COPY32  %rcx, %rax
3:  lea     L(%rsp), %rdi
    mov     $64, %esi
    lea     (L + 32)(%rsp), %rdx
    call    sha256_short
    shr     $1, %r14
    inc     %r15
    jmp     1b
4:  lea     L(%rsp), %rcx                   # hash(node + the length as 32 bytes, little endian)
    lea     (L + 32)(%rsp), %rax
    COPY32  %rcx, %rax
    lea     (L + 32)(%rsp), %rdi
    mov     $32, %esi
    call    lantern_zero
    mov     (%rbx), %rax
    mov     %rax, (L + 32)(%rsp)
    lea     L(%rsp), %rdi
    mov     $64, %esi
    mov     %r13, %rdx
    call    sha256_short
    LEAVE 64
END_FUNCTION merkle_root

/* The zero hashes of levels 0 to MERKLE_DEPTH - 1 at rdi. rbx zeros, rbp level. Locals: L a pair (64). */
LOCAL_FUNCTION merkle_zeros
    ENTER 64
    mov     %rdi, %rbx
    mov     $32, %esi
    call    lantern_zero
    mov     $1, %ebp
1:  cmp     $MERKLE_DEPTH, %rbp
    jae     2f
    lea     -1(%rbp), %rax                  # zero_hashes[level] = hash(zero_hashes[level - 1] twice)
    shl     $5, %rax
    add     %rbx, %rax
    lea     L(%rsp), %rcx
    COPY32  %rcx, %rax
    lea     (L + 32)(%rsp), %rcx
    COPY32  %rcx, %rax
    lea     L(%rsp), %rdi
    mov     $64, %esi
    mov     %rbp, %rdx
    shl     $5, %rdx
    add     %rbx, %rdx
    call    sha256_short
    inc     %rbp
    jmp     1b
2:  LEAVE 64
END_FUNCTION merkle_zeros

/* rcx = the bytes of an empty part of the genesis state with room rbp, for S7 deposits, rounded up to 8. */
.macro GENESIS_CAPACITY ref, stride, room
    mov     \room(%rbp), %rcx
    .if (\stride) == STATE_NESTED
    imul    $PENDING_ATTESTATION_ROOM, %rcx, %rcx
    .else
    .if (\room) == 0
    add     S7(%rsp), %rcx                  # the validator lists: one entry for each deposit, and the room
    .endif
    imul    $(\stride), %rcx, %rcx
    .endif
    add     $7, %rcx
    and     $-8, %rcx
.endm

.macro GENESIS_SIZE_PART ref, stride, room
    GENESIS_CAPACITY \ref, \stride, \room
    add     %rcx, %r15
.endm

/* An empty part of out r14 at cursor r15; moves the cursor. */
.macro GENESIS_WRITE_PART ref, stride, room
    GENESIS_CAPACITY \ref, \stride, \room
    mov     %r15, \ref(%r14)
    movq    $0, ((\ref) + 8)(%r14)
    add     %rcx, %r15
.endm

/* rbp room, r12 size, r15 total, S7 deposit count. */
SPEC_FUNCTION initialize_beacon_state_from_eth1_size
    ENTER 16
    mov     (%rdi), %rax
    mov     %rax, S7(%rsp)
    mov     %rsi, %rbp
    mov     %rdx, %r12
    MOVQ    %r15, BeaconState__fixed
    STATE_PARTS GENESIS_SIZE_PART
    mov     %r15, (%r12)
    xor     %eax, %eax
    LEAVE 16
SPEC_END initialize_beacon_state_from_eth1_size

/*
 * rbx eth1_block_hash, rbp room, r12 config, r13 scratch, r14 out, r15 cursor or index,
 * S7 deposit count, S8 deposits, S9 scratch size, S10 extras: tree, zeros, body.
 * Locals: L eth1_timestamp, L+8 size, L+16 result, L+24 root (32), L+56 count.
 */
SPEC_FUNCTION initialize_beacon_state_from_eth1
    ENTER 80
    mov     %rdi, %rbx
    mov     (%rsi), %rax
    mov     %rax, L(%rsp)
    mov     %rdx, S8(%rsp)
    mov     (%rcx), %rax
    mov     %rax, S7(%rsp)
    mov     %rax, (L + 56)(%rsp)
    mov     %r8, %rbp
    mov     %r9, %r12
    mov     (80 + 96)(%rsp), %r13           # the seventh and eighth arguments
    mov     (80 + 96 + 8)(%rsp), %r14
    mov     (%r13), %rax
    mov     %rax, S9(%rsp)
    lea     (L + 56)(%rsp), %rdi
    mov     %rbp, %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_initialize_beacon_state_from_eth1_size
    mov     (L + 8)(%rsp), %rax
    cmp     %rax, (%r14)
    jb      9f
    MOVQ    %rax, GENESIS_EXTRA + LANTERN_SCRATCH_FIXED
    cmp     %rax, S9(%rsp)
    jb      9f
    mov     S9(%rsp), %rax
    sub     $GENESIS_EXTRA, %rax
    add     %r13, %rax
    mov     %rax, S10(%rsp)                 # the extras, at the end of scratch
    lea     8(%r14), %rdi                   # state = BeaconState.empty(), after out's own size
    MOVQ    %rsi, BeaconState__fixed - 8
    call    lantern_zero
    mov     L(%rsp), %rax                   # genesis_time = eth1_timestamp + GENESIS_DELAY
    add     CONFIG_GENESIS_DELAY(%r12), %rax
    jc      6f
    mov     %rax, BeaconState_genesis_time(%r14)
    mov     CONFIG_GENESIS_FORK_VERSION(%r12), %eax  # fork = Fork(GENESIS_FORK_VERSION, GENESIS_FORK_VERSION, GENESIS_EPOCH)
    mov     %eax, (BeaconState_fork + Fork_previous_version)(%r14)
    mov     %eax, (BeaconState_fork + Fork_current_version)(%r14)
    mov     S7(%rsp), %rax
    mov     %rax, (BeaconState_eth1_data + Eth1Data_deposit_count)(%r14)
    lea     (BeaconState_eth1_data + Eth1Data_block_hash)(%r14), %rax
    COPY32  %rax, %rbx
    lea     BeaconState_randao_mixes(%r14), %rax    # randao_mixes = [eth1_block_hash] * EPOCHS_PER_HISTORICAL_VECTOR
    MOVQ    %rcx, EPOCHS_PER_HISTORICAL_VECTOR
1:  COPY32  %rax, %rbx
    add     $32, %rax
    dec     %rcx
    jnz     1b
    mov     S10(%rsp), %r15                 # latest_block_header.body_root = hash_tree_root(BeaconBlockBody.empty())
    add     $(TREE_BYTES + ZEROS_BYTES), %r15
    mov     %r15, %rdi
    MOVQ    %rsi, BODY_BYTES
    call    lantern_zero
    MOVQ    %rax, BeaconBlockBody__fixed
    mov     %rax, (%r15)
    .irp f, proposer_slashings, attester_slashings, attestations, deposits, voluntary_exits
    mov     %rax, BeaconBlockBody_\f(%r15)  # each list empty, after the fixed fields
    .endr
    mov     S9(%rsp), %rax
    sub     $GENESIS_EXTRA, %rax
    mov     %rax, (%r13)
    ADDRESS %rdi, lantern_type_BeaconBlockBody
    mov     %r15, %rsi
    mov     %r13, %rdx
    lea     (BeaconState_latest_block_header + BeaconBlockHeader_body_root)(%r14), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    MOVQ    %r15, BeaconState__fixed        # the parts, empty, with room
    STATE_PARTS GENESIS_WRITE_PART
    mov     S10(%rsp), %rdi                 # the deposit tree: no leaves
    movq    $0, (%rdi)
    add     $TREE_BYTES, %rdi
    call    merkle_zeros
    xor     %r15d, %r15d
2:  cmp     S7(%rsp), %r15                  # for index, deposit in enumerate(deposits)
    jae     3f
    mov     S9(%rsp), %rax
    sub     $GENESIS_EXTRA, %rax
    mov     %rax, (%r13)
    ADDRESS %rdi, lantern_type_DepositData  # the leaf: hash_tree_root(deposit.data)
    imul    $Deposit__mem, %r15, %rsi
    add     S8(%rsp), %rsi
    add     $Deposit_data, %rsi
    mov     %r13, %rdx
    lea     (L + 24)(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    mov     S10(%rsp), %rdi
    lea     (L + 24)(%rsp), %rsi
    call    merkle_add
    mov     S10(%rsp), %rdi                 # eth1_data.deposit_root = hash_tree_root(deposit_data_list)
    lea     TREE_BYTES(%rdi), %rsi
    mov     $DEPOSIT_CONTRACT_TREE_DEPTH, %edx
    lea     (BeaconState_eth1_data + Eth1Data_deposit_root)(%r14), %rcx
    call    merkle_root
    mov     S9(%rsp), %rax
    sub     $GENESIS_EXTRA, %rax
    mov     %rax, (%r13)
    mov     %r14, %rdi                      # process_deposit(state, deposit)
    imul    $Deposit__mem, %r15, %rsi
    add     S8(%rsp), %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    lea     (L + 16)(%rsp), %r8
    call    lantern_process_deposit
    test    %rax, %rax
    jnz     7f
    mov     (L + 16)(%rsp), %rax            # a failed check of the deposit
    test    %rax, %rax
    jnz     7f
    inc     %r15
    jmp     2b
3:  PART    %rsi, %rcx, %r14, BeaconState_validators   # the activations
    PART    %rdi, %rdx, %r14, BeaconState_balances
    MOVQ    %r8, EFFECTIVE_BALANCE_INCREMENT
    MOVQ    %r9, MAX_EFFECTIVE_BALANCE
4:  test    %rcx, %rcx
    jz      5f
    mov     (%rdi), %rax
    add     $8, %rdi
    xor     %edx, %edx
    div     %r8
    imul    %r8, %rax                       # balance - balance % EFFECTIVE_BALANCE_INCREMENT
    cmp     %r9, %rax
    cmova   %r9, %rax                       # min with MAX_EFFECTIVE_BALANCE
    mov     %rax, Validator_effective_balance(%rsi)
    cmp     %r9, %rax
    jne     45f
    movq    $0, Validator_activation_eligibility_epoch(%rsi)     # GENESIS_EPOCH
    movq    $0, Validator_activation_epoch(%rsi)
45: add     $Validator__mem, %rsi
    dec     %rcx
    jmp     4b
5:  mov     S10(%rsp), %rax                 # genesis_validators_root = hash_tree_root(state.validators)
    movq    $0, (%rax)
    xor     %r15d, %r15d
51: cmp     (BeaconState_validators + 8)(%r14), %r15
    jae     52f
    mov     S9(%rsp), %rax
    sub     $GENESIS_EXTRA, %rax
    mov     %rax, (%r13)
    ADDRESS %rdi, lantern_type_Validator
    PART    %rsi, %rax, %r14, BeaconState_validators
    mov     %r15, %rax
    shl     $7, %rax
    add     %rax, %rsi
    mov     %r13, %rdx
    lea     (L + 24)(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    mov     S10(%rsp), %rdi
    lea     (L + 24)(%rsp), %rsi
    call    merkle_add
    inc     %r15
    jmp     51b
52: mov     S10(%rsp), %rdi
    lea     TREE_BYTES(%rdi), %rsi
    mov     $MERKLE_DEPTH, %edx
    lea     BeaconState_genesis_validators_root(%r14), %rcx
    call    merkle_root
8:  xor     %eax, %eax
7:  mov     S9(%rsp), %rcx
    mov     %rcx, (%r13)
    LEAVE 80
6:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    jmp     7b
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 80
SPEC_END initialize_beacon_state_from_eth1

.if (Validator__mem != 128) || (STATE_NESTED != -1)
.error "genesis: the code takes 128 bytes per Validator"
.endif

SPEC_LEAF is_valid_genesis_state
    xor     %eax, %eax
    mov     BeaconState_genesis_time(%rdi), %rcx
    cmp     CONFIG_MIN_GENESIS_TIME(%rsi), %rcx     # genesis_time < MIN_GENESIS_TIME: not valid
    jb      3f
    PART    %r8, %r9, %rdi, BeaconState_validators
    xor     %ecx, %ecx
1:  test    %r9, %r9                        # the validators active at GENESIS_EPOCH: activation_epoch <= 0 < exit_epoch
    jz      2f
    cmpq    $0, Validator_activation_epoch(%r8)
    jne     15f
    cmpq    $0, Validator_exit_epoch(%r8)
    je      15f
    inc     %rcx
15: add     $Validator__mem, %r8
    dec     %r9
    jmp     1b
2:  cmp     CONFIG_MIN_GENESIS_ACTIVE_VALIDATOR_COUNT(%rsi), %rcx
    setae   %al
3:  mov     %rax, (%rdx)
    RETURN_OK
SPEC_END is_valid_genesis_state

.endif
