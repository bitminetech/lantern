/*
 * Genesis, ARM64. Requirements: docs/reference/genesis.md.
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

/* Append the 32-byte leaf x1 to tree x0, as the deposit contract does. x19 tree, x20 size, x21 level. Locals: L a pair (64). */
LOCAL_FUNCTION merkle_add
    ENTER 64
    mov     x19, x0
    add     x9, sp, #(L + 32)               /* node = leaf, in the pair's right half */
    COPY32  x9, x1
    ldr     x20, [x19]
    add     x20, x20, #1
    str     x20, [x19]
    mov     x21, #0
1:  tbnz    x20, #0, 2f                     /* an odd size: the node is the branch of this level */
    add     x9, sp, #L                      /* node = hash(branch[level] + node) */
    add     x10, x19, #8
    add     x10, x10, x21, lsl #5
    COPY32  x9, x10
    add     x0, sp, #L
    mov     x1, #64
    add     x2, sp, #(L + 32)
    bl      sha256_short
    lsr     x20, x20, #1
    add     x21, x21, #1
    cmp     x21, #MERKLE_DEPTH
    b.lo    1b
    b       3f
2:  add     x9, x19, #8
    add     x9, x9, x21, lsl #5
    add     x10, sp, #(L + 32)
    COPY32  x9, x10
3:  LEAVE 64
END_FUNCTION merkle_add

/*
 * The root of tree x0 as a list of depth x2 levels, its length mixed in, at x3; x1 holds the zero hashes.
 * x19 tree, x20 zeros, x21 depth, x22 out, x23 size, x24 level. Locals: L a pair (64).
 */
LOCAL_FUNCTION merkle_root
    ENTER 64
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    ldr     x23, [x19]
    add     x0, sp, #(L + 32)               /* node = zero, in the pair's right half */
    mov     x1, #32
    bl      lantern_zero
    mov     x24, #0
1:  cmp     x24, x21
    b.hs    4f
    tbz     x23, #0, 2f
    add     x9, sp, #L                      /* odd: hash(branch[level] + node) */
    add     x10, x19, #8
    add     x10, x10, x24, lsl #5
    COPY32  x9, x10
    b       3f
2:  add     x9, sp, #L                      /* even: hash(node + zero_hashes[level]) */
    add     x10, sp, #(L + 32)
    COPY32  x9, x10
    add     x9, sp, #(L + 32)
    add     x10, x20, x24, lsl #5
    COPY32  x9, x10
3:  add     x0, sp, #L
    mov     x1, #64
    add     x2, sp, #(L + 32)
    bl      sha256_short
    lsr     x23, x23, #1
    add     x24, x24, #1
    b       1b
4:  add     x9, sp, #L                      /* hash(node + the length as 32 bytes, little endian) */
    add     x10, sp, #(L + 32)
    COPY32  x9, x10
    add     x0, sp, #(L + 32)
    mov     x1, #32
    bl      lantern_zero
    ldr     x9, [x19]
    str     x9, [sp, #(L + 32)]
    add     x0, sp, #L
    mov     x1, #64
    mov     x2, x22
    bl      sha256_short
    LEAVE 64
END_FUNCTION merkle_root

/* The zero hashes of levels 0 to MERKLE_DEPTH - 1 at x0. x19 zeros, x20 level. Locals: L a pair (64). */
LOCAL_FUNCTION merkle_zeros
    ENTER 64
    mov     x19, x0
    mov     x1, #32
    bl      lantern_zero
    mov     x20, #1
1:  cmp     x20, #MERKLE_DEPTH
    b.hs    2f
    sub     x9, x20, #1                     /* zero_hashes[level] = hash(zero_hashes[level - 1] twice) */
    add     x10, x19, x9, lsl #5
    add     x9, sp, #L
    COPY32  x9, x10
    add     x9, sp, #(L + 32)
    COPY32  x9, x10
    add     x0, sp, #L
    mov     x1, #64
    add     x2, x19, x20, lsl #5
    bl      sha256_short
    add     x20, x20, #1
    b       1b
2:  LEAVE 64
END_FUNCTION merkle_zeros

/* x9 = the bytes of an empty part of the genesis state with room x20, for x25 deposits, rounded up to 8. Uses x13. */
.macro GENESIS_CAPACITY ref, stride, room
    ldr     x9, [x20, #\room]
    .if (\stride) == STATE_NESTED
    MOVQ    x13, PENDING_ATTESTATION_ROOM
    .else
    .if (\room) == 0
    add     x9, x9, x25                     /* the validator lists: one entry for each deposit, and the room */
    .endif
    mov     x13, #\stride
    .endif
    mul     x9, x9, x13
    add     x9, x9, #7
    and     x9, x9, #-8
.endm

.macro GENESIS_SIZE_PART ref, stride, room
    GENESIS_CAPACITY \ref, \stride, \room
    add     x24, x24, x9
.endm

/* An empty part of out x23 at cursor x24; moves the cursor. */
.macro GENESIS_WRITE_PART ref, stride, room
    GENESIS_CAPACITY \ref, \stride, \room
    STQ     x24, x23, \ref
    STQ     xzr, x23, (\ref) + 8
    add     x24, x24, x9
.endm

/* x20 room, x21 size, x24 total, x25 deposit count. */
SPEC_FUNCTION initialize_beacon_state_from_eth1_size
    ENTER 16
    ldr     x25, [x0]
    mov     x20, x1
    mov     x21, x2
    MOVQ    x24, BeaconState__fixed
    STATE_PARTS GENESIS_SIZE_PART
    str     x24, [x21]
    mov     x0, #LANTERN_OK
    LEAVE 16
SPEC_END initialize_beacon_state_from_eth1_size

/*
 * x19 eth1_block_hash, x20 room, x21 config, x22 scratch, x23 out, x24 cursor or index,
 * x25 deposit count, x26 deposits, x27 scratch size, x28 extras: tree, zeros, body.
 * Locals: L eth1_timestamp, L+8 size, L+16 result, L+24 root (32), L+56 count.
 */
SPEC_FUNCTION initialize_beacon_state_from_eth1
    ENTER 80
    mov     x19, x0
    ldr     x9, [x1]
    str     x9, [sp, #L]
    mov     x26, x2
    ldr     x25, [x3]
    mov     x20, x4
    mov     x21, x5
    mov     x22, x6
    mov     x23, x7
    ldr     x27, [x22]
    str     x25, [sp, #(L + 56)]
    add     x0, sp, #(L + 56)
    mov     x1, x20
    add     x2, sp, #(L + 8)
    bl      lantern_initialize_beacon_state_from_eth1_size
    ldr     x9, [sp, #(L + 8)]
    ldr     x10, [x23]
    cmp     x10, x9
    b.lo    9f
    MOVQ    x9, GENESIS_EXTRA + LANTERN_SCRATCH_FIXED
    cmp     x27, x9
    b.lo    9f
    MOVQ    x9, GENESIS_EXTRA
    sub     x9, x27, x9
    add     x28, x22, x9                    /* the extras, at the end of scratch */
    add     x0, x23, #8                     /* state = BeaconState.empty(), after out's own size */
    MOVQ    x1, BeaconState__fixed - 8
    bl      lantern_zero
    ldr     x9, [sp, #L]                    /* genesis_time = eth1_timestamp + GENESIS_DELAY */
    ldr     x10, [x21, #CONFIG_GENESIS_DELAY]
    adds    x9, x9, x10
    b.cs    6f
    STQ     x9, x23, BeaconState_genesis_time
    ldr     w9, [x21, #CONFIG_GENESIS_FORK_VERSION]  /* fork = Fork(GENESIS_FORK_VERSION, GENESIS_FORK_VERSION, GENESIS_EPOCH) */
    ADDQ    x10, x23, BeaconState_fork
    str     w9, [x10, #Fork_previous_version]
    str     w9, [x10, #Fork_current_version]
    STQ     x25, x23, BeaconState_eth1_data + Eth1Data_deposit_count
    ADDQ    x9, x23, BeaconState_eth1_data + Eth1Data_block_hash
    COPY32  x9, x19
    ADDQ    x24, x23, BeaconState_randao_mixes  /* randao_mixes = [eth1_block_hash] * EPOCHS_PER_HISTORICAL_VECTOR */
    MOVQ    x11, EPOCHS_PER_HISTORICAL_VECTOR
1:  COPY32  x24, x19
    add     x24, x24, #32
    subs    x11, x11, #1
    b.ne    1b
    MOVQ    x9, TREE_BYTES + ZEROS_BYTES    /* latest_block_header.body_root = hash_tree_root(BeaconBlockBody.empty()) */
    add     x24, x28, x9
    mov     x0, x24
    MOVQ    x1, BODY_BYTES
    bl      lantern_zero
    MOVQ    x9, BeaconBlockBody__fixed
    str     x9, [x24]
    .irp f, proposer_slashings, attester_slashings, attestations, deposits, voluntary_exits
    STQ     x9, x24, BeaconBlockBody_\f     /* each list empty, after the fixed fields */
    .endr
    MOVQ    x9, GENESIS_EXTRA
    sub     x9, x27, x9
    str     x9, [x22]
    ADDRESS x0, lantern_type_BeaconBlockBody
    mov     x1, x24
    mov     x2, x22
    ADDQ    x3, x23, BeaconState_latest_block_header + BeaconBlockHeader_body_root
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    MOVQ    x24, BeaconState__fixed         /* the parts, empty, with room */
    STATE_PARTS GENESIS_WRITE_PART
    str     xzr, [x28]                      /* the deposit tree: no leaves */
    MOVQ    x9, TREE_BYTES
    add     x0, x28, x9
    bl      merkle_zeros
    mov     x24, #0
2:  cmp     x24, x25                        /* for index, deposit in enumerate(deposits) */
    b.hs    3f
    MOVQ    x9, GENESIS_EXTRA
    sub     x9, x27, x9
    str     x9, [x22]
    ADDRESS x0, lantern_type_DepositData    /* the leaf: hash_tree_root(deposit.data) */
    MOVQ    x9, Deposit__mem
    madd    x1, x24, x9, x26
    ADDQ    x1, x1, Deposit_data
    mov     x2, x22
    add     x3, sp, #(L + 24)
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    mov     x0, x28
    add     x1, sp, #(L + 24)
    bl      merkle_add
    mov     x0, x28                         /* eth1_data.deposit_root = hash_tree_root(deposit_data_list) */
    MOVQ    x9, TREE_BYTES
    add     x1, x28, x9
    mov     x2, #DEPOSIT_CONTRACT_TREE_DEPTH
    ADDQ    x3, x23, BeaconState_eth1_data + Eth1Data_deposit_root
    bl      merkle_root
    MOVQ    x9, GENESIS_EXTRA
    sub     x9, x27, x9
    str     x9, [x22]
    mov     x0, x23                         /* process_deposit(state, deposit) */
    MOVQ    x9, Deposit__mem
    madd    x1, x24, x9, x26
    mov     x2, x21
    mov     x3, x22
    add     x4, sp, #(L + 16)
    bl      lantern_process_deposit
    cbnz    x0, 7f
    ldr     x0, [sp, #(L + 16)]             /* a failed check of the deposit */
    cbnz    x0, 7f
    add     x24, x24, #1
    b       2b
3:  PART    x11, x12, x23, BeaconState_validators   /* the activations */
    PART    x13, x14, x23, BeaconState_balances
    MOVQ    x15, EFFECTIVE_BALANCE_INCREMENT
    MOVQ    x14, MAX_EFFECTIVE_BALANCE
4:  cbz     x12, 5f
    ldr     x9, [x13], #8
    udiv    x10, x9, x15
    mul     x10, x10, x15                   /* balance - balance % EFFECTIVE_BALANCE_INCREMENT */
    cmp     x10, x14
    csel    x10, x10, x14, lo               /* min with MAX_EFFECTIVE_BALANCE */
    str     x10, [x11, #Validator_effective_balance]
    cmp     x10, x14
    b.ne    45f
    str     xzr, [x11, #Validator_activation_eligibility_epoch]     /* GENESIS_EPOCH */
    str     xzr, [x11, #Validator_activation_epoch]
45: add     x11, x11, #Validator__mem
    sub     x12, x12, #1
    b       4b
5:  str     xzr, [x28]                      /* genesis_validators_root = hash_tree_root(state.validators) */
    mov     x24, #0
51: LDQ     x9, x23, BeaconState_validators + 8
    cmp     x24, x9
    b.hs    52f
    MOVQ    x9, GENESIS_EXTRA
    sub     x9, x27, x9
    str     x9, [x22]
    ADDRESS x0, lantern_type_Validator
    PART    x1, x9, x23, BeaconState_validators
    add     x1, x1, x24, lsl #7
    mov     x2, x22
    add     x3, sp, #(L + 24)
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    mov     x0, x28
    add     x1, sp, #(L + 24)
    bl      merkle_add
    add     x24, x24, #1
    b       51b
52: mov     x0, x28
    MOVQ    x9, TREE_BYTES
    add     x1, x28, x9
    mov     x2, #MERKLE_DEPTH
    ADDQ    x3, x23, BeaconState_genesis_validators_root
    bl      merkle_root
8:  mov     x0, #LANTERN_OK
7:  str     x27, [x22]
    LEAVE 80
6:  mov     x0, #LANTERN_INVALID_OVERFLOW
    b       7b
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
SPEC_END initialize_beacon_state_from_eth1

.if (Validator__mem != 128) || (STATE_NESTED != -1)
.error "genesis: the code takes 128 bytes per Validator"
.endif

SPEC_LEAF is_valid_genesis_state
    LDQ     x3, x0, BeaconState_genesis_time
    ldr     x4, [x1, #CONFIG_MIN_GENESIS_TIME]
    mov     x5, #0
    cmp     x3, x4                          /* genesis_time < MIN_GENESIS_TIME: not valid */
    b.lo    3f
    PART    x6, x7, x0, BeaconState_validators
    mov     x8, #0
1:  cbz     x7, 2f                          /* the validators active at GENESIS_EPOCH: activation_epoch <= 0 < exit_epoch */
    ldr     x9, [x6, #Validator_activation_epoch]
    ldr     x10, [x6, #Validator_exit_epoch]
    add     x6, x6, #Validator__mem
    sub     x7, x7, #1
    cbnz    x9, 1b
    cbz     x10, 1b
    add     x8, x8, #1
    b       1b
2:  ldr     x4, [x1, #CONFIG_MIN_GENESIS_ACTIVE_VALIDATOR_COUNT]
    cmp     x8, x4
    cset    x5, hs
3:  str     x5, [x2]
    RETURN_OK
SPEC_END is_valid_genesis_state

.endif
