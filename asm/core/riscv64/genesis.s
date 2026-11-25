/*
 * Genesis, RISC-V. Requirements: docs/reference/genesis.md.
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

/* Append the 32-byte leaf a1 to tree a0, as the deposit contract does. s1 tree, s2 size, s3 level. Locals: L a pair (64). */
LOCAL_FUNCTION lantern_merkle_add
    ENTER 64
    mv      s1, a0
    addi    t0, sp, (L + 32)                # node = leaf, in the pair's right half
    COPY32  t0, a1
    ld      s2, 0(s1)
    addi    s2, s2, 1
    sd      s2, 0(s1)
    li      s3, 0
1:  andi    t0, s2, 1                       # an odd size: the node is the branch of this level
    bnez    t0, 2f
    slli    t1, s3, 5                       # node = hash(branch[level] + node)
    add     t1, s1, t1
    addi    t1, t1, 8
    addi    t0, sp, L
    COPY32  t0, t1
    addi    a0, sp, L
    li      a1, 64
    addi    a2, sp, (L + 32)
    call    lantern_sha256_short
    srli    s2, s2, 1
    addi    s3, s3, 1
    li      t0, MERKLE_DEPTH
    bltu    s3, t0, 1b
    j       3f
2:  slli    t1, s3, 5
    add     t1, s1, t1
    addi    t1, t1, 8
    addi    t0, sp, (L + 32)
    COPY32  t1, t0
3:  LEAVE 64
END_FUNCTION lantern_merkle_add

/*
 * The root of tree a0 as a list of depth a2 levels, its length mixed in, at a3; a1 holds the zero hashes.
 * s1 tree, s2 zeros, s3 depth, s4 out, s5 size, s6 level. Locals: L a pair (64).
 */
LOCAL_FUNCTION lantern_merkle_root
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    ld      s5, 0(s1)
    addi    a0, sp, (L + 32)                # node = zero, in the pair's right half
    li      a1, 32
    call    lantern_zero
    li      s6, 0
1:  bgeu    s6, s3, 4f
    andi    t0, s5, 1
    beqz    t0, 2f
    slli    t1, s6, 5                       # odd: hash(branch[level] + node)
    add     t1, s1, t1
    addi    t1, t1, 8
    addi    t0, sp, L
    COPY32  t0, t1
    j       3f
2:  addi    t0, sp, L                       # even: hash(node + zero_hashes[level])
    addi    t1, sp, (L + 32)
    COPY32  t0, t1
    slli    t1, s6, 5
    add     t1, s2, t1
    addi    t0, sp, (L + 32)
    COPY32  t0, t1
3:  addi    a0, sp, L
    li      a1, 64
    addi    a2, sp, (L + 32)
    call    lantern_sha256_short
    srli    s5, s5, 1
    addi    s6, s6, 1
    j       1b
4:  addi    t0, sp, L                       # hash(node + the length as 32 bytes, little endian)
    addi    t1, sp, (L + 32)
    COPY32  t0, t1
    addi    a0, sp, (L + 32)
    li      a1, 32
    call    lantern_zero
    ld      t0, 0(s1)
    sd      t0, (L + 32)(sp)
    addi    a0, sp, L
    li      a1, 64
    mv      a2, s4
    call    lantern_sha256_short
    LEAVE 64
END_FUNCTION lantern_merkle_root

/* The zero hashes of levels 0 to MERKLE_DEPTH - 1 at a0. s1 zeros, s2 level. Locals: L a pair (64). */
LOCAL_FUNCTION lantern_merkle_zeros
    ENTER 64
    mv      s1, a0
    li      a1, 32
    call    lantern_zero
    li      s2, 1
1:  li      t0, MERKLE_DEPTH
    bgeu    s2, t0, 2f
    addi    t1, s2, -1                      # zero_hashes[level] = hash(zero_hashes[level - 1] twice)
    slli    t1, t1, 5
    add     t1, s1, t1
    addi    t0, sp, L
    COPY32  t0, t1
    addi    t0, sp, (L + 32)
    COPY32  t0, t1
    addi    a0, sp, L
    li      a1, 64
    slli    a2, s2, 5
    add     a2, s1, a2
    call    lantern_sha256_short
    addi    s2, s2, 1
    j       1b
2:  LEAVE 64
END_FUNCTION lantern_merkle_zeros

/* t1 = the bytes of an empty part of the genesis state with room s2, for s7 deposits, rounded up to 8. Uses t2. */
.macro GENESIS_CAPACITY ref, stride, room
    ld      t1, \room(s2)
    .if (\stride) == STATE_NESTED
    li      t2, PENDING_ATTESTATION_ROOM
    .else
    .if (\room) == 0
    add     t1, t1, s7                      # the validator lists: one entry for each deposit, and the room
    .endif
    li      t2, \stride
    .endif
    mul     t1, t1, t2
    addi    t1, t1, 7
    andi    t1, t1, -8
.endm

.macro GENESIS_SIZE_PART ref, stride, room
    GENESIS_CAPACITY \ref, \stride, \room
    add     s6, s6, t1
.endm

/* An empty part of out s5 at cursor s6; moves the cursor. */
.macro GENESIS_WRITE_PART ref, stride, room
    GENESIS_CAPACITY \ref, \stride, \room
    STQ     s6, s5, \ref
    STQ     zero, s5, (\ref) + 8
    add     s6, s6, t1
.endm

/* s2 room, s3 size, s6 total, s7 deposit count. */
SPEC_FUNCTION initialize_beacon_state_from_eth1_size
    ENTER 16
    ld      s7, 0(a0)
    mv      s2, a1
    mv      s3, a2
    li      s6, BeaconState__fixed
    STATE_PARTS GENESIS_SIZE_PART
    sd      s6, 0(s3)
    li      a0, LANTERN_OK
    LEAVE 16
SPEC_END initialize_beacon_state_from_eth1_size

/*
 * s1 eth1_block_hash, s2 room, s3 config, s4 scratch, s5 out, s6 cursor or index,
 * s7 deposit count, s8 deposits, s9 scratch size, s10 extras: tree, zeros, body.
 * Locals: L eth1_timestamp, L+8 size, L+16 result, L+24 root (32), L+56 count.
 */
SPEC_FUNCTION initialize_beacon_state_from_eth1
    ENTER 80
    mv      s4, a6                          # before any macro, which may use a6 and a7
    mv      s5, a7
    mv      s1, a0
    ld      t0, 0(a1)
    sd      t0, L(sp)
    mv      s8, a2
    ld      s7, 0(a3)
    mv      s2, a4
    mv      s3, a5
    ld      s9, 0(s4)
    sd      s7, (L + 56)(sp)
    addi    a0, sp, (L + 56)
    mv      a1, s2
    addi    a2, sp, (L + 8)
    call    lantern_initialize_beacon_state_from_eth1_size
    ld      t0, (L + 8)(sp)
    ld      t1, 0(s5)
    bltu    t1, t0, 9f
    li      t0, GENESIS_EXTRA + LANTERN_SCRATCH_FIXED
    bltu    s9, t0, 9f
    li      t0, GENESIS_EXTRA
    sub     t0, s9, t0
    add     s10, s4, t0                     # the extras, at the end of scratch
    addi    a0, s5, 8                       # state = BeaconState.empty(), after out's own size
    li      a1, BeaconState__fixed - 8
    call    lantern_zero
    ld      t0, L(sp)                       # genesis_time = eth1_timestamp + GENESIS_DELAY
    LDQ     t1, s3, CONFIG_GENESIS_DELAY
    add     t1, t0, t1
    bltu    t1, t0, 6f
    STQ     t1, s5, BeaconState_genesis_time
    lw      t0, CONFIG_GENESIS_FORK_VERSION(s3)  # fork = Fork(GENESIS_FORK_VERSION, GENESIS_FORK_VERSION, GENESIS_EPOCH)
    ADDQ    t1, s5, BeaconState_fork
    sw      t0, Fork_previous_version(t1)
    sw      t0, Fork_current_version(t1)
    STQ     s7, s5, BeaconState_eth1_data + Eth1Data_deposit_count
    ADDQ    t0, s5, BeaconState_eth1_data + Eth1Data_block_hash
    COPY32  t0, s1
    ADDQ    t0, s5, BeaconState_randao_mixes  # randao_mixes = [eth1_block_hash] * EPOCHS_PER_HISTORICAL_VECTOR
    li      t1, EPOCHS_PER_HISTORICAL_VECTOR
1:  COPY32  t0, s1
    addi    t0, t0, 32
    addi    t1, t1, -1
    bnez    t1, 1b
    li      t0, TREE_BYTES + ZEROS_BYTES    # latest_block_header.body_root = hash_tree_root(BeaconBlockBody.empty())
    add     s6, s10, t0
    mv      a0, s6
    li      a1, BODY_BYTES
    call    lantern_zero
    li      t0, BeaconBlockBody__fixed
    sd      t0, 0(s6)
    .irp f, proposer_slashings, attester_slashings, attestations, deposits, voluntary_exits
    STQ     t0, s6, BeaconBlockBody_\f      # each list empty, after the fixed fields
    .endr
    li      t0, GENESIS_EXTRA
    sub     t0, s9, t0
    sd      t0, 0(s4)
    ADDRESS a0, lantern_type_BeaconBlockBody
    mv      a1, s6
    mv      a2, s4
    ADDQ    a3, s5, BeaconState_latest_block_header + BeaconBlockHeader_body_root
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 7f
    li      s6, BeaconState__fixed          # the parts, empty, with room
    STATE_PARTS GENESIS_WRITE_PART
    sd      zero, 0(s10)                    # the deposit tree: no leaves
    li      t0, TREE_BYTES
    add     a0, s10, t0
    call    lantern_merkle_zeros
    li      s6, 0
2:  bgeu    s6, s7, 3f                      # for index, deposit in enumerate(deposits)
    li      t0, GENESIS_EXTRA
    sub     t0, s9, t0
    sd      t0, 0(s4)
    ADDRESS a0, lantern_type_DepositData    # the leaf: hash_tree_root(deposit.data)
    li      t0, Deposit__mem
    mul     t0, s6, t0
    add     a1, s8, t0
    ADDQ    a1, a1, Deposit_data
    mv      a2, s4
    addi    a3, sp, (L + 24)
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 7f
    mv      a0, s10
    addi    a1, sp, (L + 24)
    call    lantern_merkle_add
    mv      a0, s10                         # eth1_data.deposit_root = hash_tree_root(deposit_data_list)
    li      t0, TREE_BYTES
    add     a1, s10, t0
    li      a2, DEPOSIT_CONTRACT_TREE_DEPTH
    ADDQ    a3, s5, BeaconState_eth1_data + Eth1Data_deposit_root
    call    lantern_merkle_root
    li      t0, GENESIS_EXTRA
    sub     t0, s9, t0
    sd      t0, 0(s4)
    mv      a0, s5                          # process_deposit(state, deposit)
    li      t0, Deposit__mem
    mul     t0, s6, t0
    add     a1, s8, t0
    mv      a2, s3
    mv      a3, s4
    addi    a4, sp, (L + 16)
    call    lantern_process_deposit
    bnez    a0, 7f
    ld      a0, (L + 16)(sp)                # a failed check of the deposit
    bnez    a0, 7f
    addi    s6, s6, 1
    j       2b
3:  PART    t0, t1, s5, BeaconState_validators  # the activations
    PART    t2, t3, s5, BeaconState_balances
    li      t4, EFFECTIVE_BALANCE_INCREMENT
    li      t5, MAX_EFFECTIVE_BALANCE
4:  beqz    t1, 5f
    ld      t6, 0(t2)
    addi    t2, t2, 8
    remu    a1, t6, t4
    sub     t6, t6, a1                      # balance - balance % EFFECTIVE_BALANCE_INCREMENT
    bleu    t6, t5, 41f
    mv      t6, t5                          # min with MAX_EFFECTIVE_BALANCE
41: sd      t6, Validator_effective_balance(t0)
    bne     t6, t5, 45f
    sd      zero, Validator_activation_eligibility_epoch(t0)  # GENESIS_EPOCH
    sd      zero, Validator_activation_epoch(t0)
45: addi    t0, t0, Validator__mem
    addi    t1, t1, -1
    j       4b
5:  sd      zero, 0(s10)                    # genesis_validators_root = hash_tree_root(state.validators)
    li      s6, 0
51: LDQ     t0, s5, BeaconState_validators + 8
    bgeu    s6, t0, 52f
    li      t0, GENESIS_EXTRA
    sub     t0, s9, t0
    sd      t0, 0(s4)
    ADDRESS a0, lantern_type_Validator
    PART    a1, t0, s5, BeaconState_validators
    slli    t1, s6, 7
    add     a1, a1, t1
    mv      a2, s4
    addi    a3, sp, (L + 24)
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 7f
    mv      a0, s10
    addi    a1, sp, (L + 24)
    call    lantern_merkle_add
    addi    s6, s6, 1
    j       51b
52: mv      a0, s10
    li      t0, TREE_BYTES
    add     a1, s10, t0
    li      a2, MERKLE_DEPTH
    ADDQ    a3, s5, BeaconState_genesis_validators_root
    call    lantern_merkle_root
8:  li      a0, LANTERN_OK
7:  sd      s9, 0(s4)
    LEAVE 80
6:  li      a0, LANTERN_INVALID_OVERFLOW
    j       7b
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
SPEC_END initialize_beacon_state_from_eth1

.if (Validator__mem != 128) || (STATE_NESTED != -1)
.error "genesis: the code takes 128 bytes per Validator"
.endif

SPEC_LEAF is_valid_genesis_state
    LDQ     t0, a0, BeaconState_genesis_time
    LDQ     t1, a1, CONFIG_MIN_GENESIS_TIME
    li      t2, 0
    bltu    t0, t1, 3f                      # genesis_time < MIN_GENESIS_TIME: not valid
    PART    t3, t4, a0, BeaconState_validators
    li      t5, 0
1:  beqz    t4, 2f                          # the validators active at GENESIS_EPOCH: activation_epoch <= 0 < exit_epoch
    ld      t0, Validator_activation_epoch(t3)
    ld      t1, Validator_exit_epoch(t3)
    addi    t3, t3, Validator__mem
    addi    t4, t4, -1
    bnez    t0, 1b
    beqz    t1, 1b
    addi    t5, t5, 1
    j       1b
2:  LDQ     t1, a1, CONFIG_MIN_GENESIS_ACTIVE_VALIDATOR_COUNT
    sltu    t2, t5, t1
    xori    t2, t2, 1
3:  sd      t2, 0(a2)
    RETURN_OK
SPEC_END is_valid_genesis_state

.endif
