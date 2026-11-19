/*
 * Phase0's epoch accounting by PendingAttestation, RISC-V: the matching attestations, their
 * unslashed attesting indices and balance, the attestation deltas, and the epoch steps that
 * read them. Requirements: docs/reference/epoch-processing.md.
 *
 * A list of matching attestations is an IndexList of the offsets of PendingAttestation values
 * from the start of the state, in the order of the state's list.
 */

/* The IndexList of the matching attestations of one epoch, at the end of a function's scratch. */
.set PENDING_REFS_BYTES, LIST_FIXED + 8 * MAX_ATTESTATIONS * SLOTS_PER_EPOCH

/* dst = get_base_reward of a validator of effective balance eb, with the square root of the total active balance in sqrt. Uses a7. */
.macro BASE_REWARD dst, eb, sqrt
    li      a7, BASE_REWARD_FACTOR
    mul     \dst, \eb, a7
    divu    \dst, \dst, \sqrt
    srli    \dst, \dst, 2                   # // BASE_REWARDS_PER_EPOCH, which is 4
.endm
.if BASE_REWARDS_PER_EPOCH != 4
.error "BASE_REWARD divides by BASE_REWARDS_PER_EPOCH with a shift by 2"
.endif

/* Take the refs list from the end of scratch s: refs = its last PENDING_REFS_BYTES, tot = the bytes before. Uses a7. */
.macro TAKE_REFS refs, s, tot
    ld      \tot, 0(\s)
    li      a7, PENDING_REFS_BYTES
    sub     \tot, \tot, a7
    add     \refs, \s, \tot
    sd      a7, 0(\refs)
    sd      \tot, 0(\s)
.endm

/* ---------------------------------------------------------------- Matching attestations */

/* s1 state, s2 out, s3 epoch. Locals: L previous epoch, L+8 current epoch. */
SPEC_FUNCTION get_matching_source_attestations
    ENTER 16
    mv      s1, a0
    ld      s3, 0(a1)
    mv      s2, a2
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_previous_epoch
    mv      a0, s1
    addi    a1, sp, (L + 8)
    call    lantern_get_current_epoch
    ld      t0, L(sp)
    ld      t1, (L + 8)(sp)
    bne     s3, t1, 1f                      # the current epoch's list when epoch is current
    li      t2, BeaconState_current_epoch_attestations
    j       2f
1:  bne     s3, t0, 8f                      # assert epoch in (previous, current)
    li      t2, BeaconState_previous_epoch_attestations
2:  add     t2, s1, t2
    ld      t3, 0(t2)                       # the part's offset
    ld      t4, 8(t2)                       # its count
    slli    t5, t4, 3
    addi    t5, t5, LIST_FIXED
    ld      t6, LIST_SIZE(s2)
    bltu    t6, t5, 9f
    li      t5, LIST_FIXED
    sd      t5, LIST_OFFSET(s2)
    sd      t4, LIST_COUNT(s2)
    addi    t5, s2, LIST_FIXED
3:  beqz    t4, 4f
    sd      t3, 0(t5)
    addi    t5, t5, 8
    add     t6, s1, t3                      # the next value starts after this one's size
    ld      t6, 0(t6)
    add     t3, t3, t6
    addi    t4, t4, -1
    j       3b
4:  li      a0, LANTERN_OK
    LEAVE 16
8:  li      a0, LANTERN_INVALID_PARTICIPATION_EPOCH
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_matching_source_attestations

/* Keep the refs of out s2 for which the 32 bytes at offset off of the attestation equal the root at L. Uses t0-t5, a6, a7. */
.macro KEEP_MATCHING off
    addi    t0, s2, LIST_FIXED
    mv      t1, t0
    ld      t2, LIST_COUNT(s2)
    slli    t2, t2, 3
    add     t2, t0, t2
91: bgeu    t0, t2, 93f
    ld      t3, 0(t0)
    addi    t0, t0, 8
    add     t4, s1, t3
    ADDQ    t4, t4, (\off)
    addi    t5, sp, L
    NE32    t4, t5, 91b
    sd      t3, 0(t1)
    addi    t1, t1, 8
    j       91b
93: sub     t1, t1, s2
    addi    t1, t1, -LIST_FIXED
    srli    t1, t1, 3
    sd      t1, LIST_COUNT(s2)
.endm

/* s1 state, s2 out, s3 epoch. Locals: L the epoch's block root (32). */
SPEC_FUNCTION get_matching_target_attestations
    ENTER 32
    mv      s1, a0
    mv      s3, a1
    mv      s2, a2
    call    lantern_get_matching_source_attestations
    bnez    a0, 7f
    ld      t0, LIST_COUNT(s2)              # the spec reads the root inside the comprehension: none for no attestation
    beqz    t0, 8f
    mv      a0, s1                          # a.data.target.root == get_block_root(state, epoch)
    mv      a1, s3
    addi    a2, sp, L
    call    lantern_get_block_root
    bnez    a0, 7f
    KEEP_MATCHING (PendingAttestation_data + AttestationData_target + Checkpoint_root)
8:  li      a0, LANTERN_OK
7:  LEAVE 32
SPEC_END get_matching_target_attestations

/* s1 state, s2 out, s3 epoch, s4 cursor, s5 kept, s6 end, s7 the attestation, s8 its ref. Locals: L root (32). */
SPEC_FUNCTION get_matching_head_attestations
    ENTER 32
    mv      s1, a0
    mv      s3, a1
    mv      s2, a2
    call    lantern_get_matching_target_attestations
    bnez    a0, 7f
    addi    s4, s2, LIST_FIXED
    mv      s5, s4
    ld      t0, LIST_COUNT(s2)
    slli    t0, t0, 3
    add     s6, s4, t0
1:  bgeu    s4, s6, 3f
    ld      s8, 0(s4)
    addi    s4, s4, 8
    add     s7, s1, s8
    mv      a0, s1                          # a.data.beacon_block_root == get_block_root_at_slot(state, a.data.slot)
    addi    a1, s7, (PendingAttestation_data + AttestationData_slot)
    addi    a2, sp, L
    call    lantern_get_block_root_at_slot
    bnez    a0, 7f
    addi    t0, s7, (PendingAttestation_data + AttestationData_beacon_block_root)
    addi    t1, sp, L
    NE32    t0, t1, 1b
    sd      s8, 0(s5)
    addi    s5, s5, 8
    j       1b
3:  sub     t0, s5, s2
    addi    t0, t0, -LIST_FIXED
    srli    t0, t0, 3
    sd      t0, LIST_COUNT(s2)
    li      a0, LANTERN_OK
7:  LEAVE 32
SPEC_END get_matching_head_attestations

/* ---------------------------------------------------------------- Attesting indices and balance */

/*
 * s1 state, s2 attestations, s3 scratch, s4 out, s5 scratch size, s6 n, s7 a byte per
 * validator, s8 one attestation's attesting indices, s9 cursor, s10 end.
 * Scratch: list 0 the bytes, list 1 the attesting indices, then get_attesting_indices's S(3).
 */
SPEC_FUNCTION get_unslashed_attesting_indices
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH s3, s1, 5, 9f
    LDQ     s6, s1, BeaconState_validators + 8
    slli    t0, s6, 3                       # out has room for every validator
    addi    t0, t0, LIST_FIXED
    ld      t1, LIST_SIZE(s4)
    bltu    t1, t0, 9f
    ld      s5, 0(s3)
    SCRATCH_LIST s7, s3, s5, 0, s6
    SCRATCH_LIST s8, s3, s5, 1, s6
    addi    a0, s7, LIST_FIXED
    mv      a1, s6
    call    lantern_zero
    addi    s9, s2, LIST_FIXED
    ld      t0, LIST_COUNT(s2)
    slli    t0, t0, 3
    add     s10, s9, t0
1:  bgeu    s9, s10, 3f                     # output = union of get_attesting_indices(state, a)
    ld      t0, 0(s9)
    addi    s9, s9, 8
    SCRATCH_GIVE s3, s5, 2, s6
    mv      a0, s1
    add     a1, s1, t0
    mv      a3, s3
    mv      a4, s8
    li      a2, 0
    call    lantern_get_attesting_indices
    bnez    a0, 7f
    ld      t0, LIST_COUNT(s8)
    addi    t1, s8, LIST_FIXED
    addi    t2, s7, LIST_FIXED
    li      t3, 1
2:  beqz    t0, 1b
    ld      t4, 0(t1)
    addi    t1, t1, 8
    add     t4, t2, t4
    sb      t3, 0(t4)
    addi    t0, t0, -1
    j       2b
3:  li      t0, LIST_FIXED                  # the set, ascending, without the slashed
    sd      t0, LIST_OFFSET(s4)
    PART    t1, t2, s1, BeaconState_validators
    addi    t2, s7, LIST_FIXED
    addi    t3, s4, LIST_FIXED
    li      t4, 0
    li      t5, 0
4:  bgeu    t4, s6, 5f
    add     t6, t2, t4
    lbu     t6, 0(t6)
    beqz    t6, 45f
    lbu     t6, Validator_slashed(t1)
    bnez    t6, 45f
    sd      t4, 0(t3)
    addi    t3, t3, 8
    addi    t5, t5, 1
45: addi    t4, t4, 1
    addi    t1, t1, Validator__mem
    j       4b
5:  sd      t5, LIST_COUNT(s4)
    li      a0, LANTERN_OK
7:  LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_unslashed_attesting_indices

/* s1 state, s2 attestations, s3 scratch, s4 out, s5 scratch size, s6 n, s7 the indices. Scratch: list 0, then S(5). */
SPEC_FUNCTION get_attesting_balance
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH s3, s1, 6, 9f
    LDQ     s6, s1, BeaconState_validators + 8
    ld      s5, 0(s3)
    SCRATCH_LIST s7, s3, s5, 0, s6
    SCRATCH_GIVE s3, s5, 1, s6
    mv      a0, s1
    mv      a1, s2
    mv      a2, s3
    mv      a3, s7
    call    lantern_get_unslashed_attesting_indices
    bnez    a0, 7f
    mv      a0, s1                          # get_total_balance(state, get_unslashed_attesting_indices(...))
    mv      a1, s7
    mv      a2, s4
    call    lantern_get_total_balance
7:  LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_attesting_balance

/* ---------------------------------------------------------------- Rewards and penalties */

/* Locals: sp+0 out, sp+8 base reward. */
SPEC_FUNCTION get_proposer_reward
    FRAME 16
    sd      a3, 0(sp)
    addi    a3, sp, 8
    call    lantern_get_base_reward
    bnez    a0, 1f
    ld      t0, 8(sp)
    li      t1, PROPOSER_REWARD_QUOTIENT
    divu    t0, t0, t1
    ld      t1, 0(sp)
    sd      t0, 0(t1)
    li      a0, LANTERN_OK
1:  UNFRAME 16
SPEC_END get_proposer_reward

/*
 * s1 state, s2 attestations, s3 scratch, s4 rewards, s5 penalties, s6 n, s7 unslashed,
 * s8 eligible, s9 cursor over unslashed, s10 its end.
 * Locals: L total balance, L+8 its square root, L+16 attesting balance, L+24 in leak, L+32 scratch size.
 * Scratch: list 0 unslashed, list 1 eligible, then get_unslashed_attesting_indices's S(5).
 */
SPEC_FUNCTION get_attestation_component_deltas
    ENTER 48
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    NEED_SCRATCH s3, s1, 7, 9f
    LDQ     s6, s1, BeaconState_validators + 8
    ld      t0, 0(s3)
    sd      t0, (L + 32)(sp)
    mv      a0, s4
    mv      a1, s6
    call    zero_deltas
    mv      a0, s5
    mv      a1, s6
    call    zero_deltas
    ld      t0, (L + 32)(sp)
    SCRATCH_LIST s7, s3, t0, 0, s6
    SCRATCH_LIST s8, s3, t0, 1, s6
    SCRATCH_GIVE s3, t0, 2, s6
    mv      a0, s1                          # total_balance = get_total_active_balance(state)
    mv      a1, s3
    addi    a2, sp, L
    call    lantern_get_total_active_balance
    bnez    a0, 7f
    addi    a0, sp, L
    addi    a1, sp, (L + 8)
    call    lantern_integer_squareroot
    ld      t0, (L + 32)(sp)
    SCRATCH_GIVE s3, t0, 2, s6
    mv      a0, s1
    mv      a1, s2
    mv      a2, s3
    mv      a3, s7
    call    lantern_get_unslashed_attesting_indices
    bnez    a0, 7f
    mv      a0, s1                          # attesting_balance = get_total_balance(state, unslashed_attesting_indices)
    mv      a1, s7
    addi    a2, sp, (L + 16)
    call    lantern_get_total_balance
    mv      a0, s1
    mv      a1, s8
    call    lantern_get_eligible_validator_indices
    bnez    a0, 7f
    mv      a0, s1
    addi    a1, sp, (L + 24)
    call    lantern_is_in_inactivity_leak
    addi    s9, s7, LIST_FIXED
    ld      t0, LIST_COUNT(s7)
    slli    t0, t0, 3
    add     s10, s9, t0
    addi    t0, s8, LIST_FIXED              # for index in get_eligible_validator_indices(state)
    ld      t1, LIST_COUNT(s8)
    slli    t1, t1, 3
    add     t1, t0, t1
    PART    t2, t3, s1, BeaconState_validators
    ld      t3, (L + 8)(sp)
    ld      t4, (L + 24)(sp)
    li      a5, EFFECTIVE_BALANCE_INCREMENT
    ld      t5, L(sp)
    divu    t5, t5, a5                      # total_balance // increment
    ld      t6, (L + 16)(sp)
    divu    t6, t6, a5                      # attesting_balance // increment
    addi    a2, s4, LIST_FIXED
    addi    a3, s5, LIST_FIXED
1:  bgeu    t0, t1, 5f
    ld      a4, 0(t0)
    addi    t0, t0, 8
    slli    a5, a4, 7
    add     a5, t2, a5
    ld      a5, Validator_effective_balance(a5)
    BASE_REWARD a5, a5, t3
    IN_SORTED a4, s9, s10, a0
    slli    a4, a4, 3
    beqz    a0, 3f
    mv      a1, a5                          # in leak: the full base reward
    bnez    t4, 2f
    mulhu   a1, a5, t6                      # else base_reward * (attesting_balance // increment) // (total_balance // increment)
    bnez    a1, 8f
    mul     a1, a5, t6
    divu    a1, a1, t5
2:  add     a4, a2, a4
    ld      a0, 0(a4)
    add     a1, a0, a1
    bltu    a1, a0, 8f
    sd      a1, 0(a4)
    j       1b
3:  add     a4, a3, a4                      # not attesting: penalties[index] += base_reward
    ld      a0, 0(a4)
    add     a1, a0, a5
    bltu    a1, a0, 8f
    sd      a1, 0(a4)
    j       1b
5:  li      a0, LANTERN_OK
7:  LEAVE 48
8:  li      a0, LANTERN_INVALID_OVERFLOW
    LEAVE 48
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END get_attestation_component_deltas

/*
 * get_source_deltas, get_target_deltas, get_head_deltas: the component deltas of the matching
 * attestations of the previous epoch. s1 state, s2 scratch, s3 rewards, s4 penalties,
 * s5 refs, s6 scratch size without the refs. Locals: L previous epoch.
 * Scratch: the refs at the end, then get_attestation_component_deltas's S(7).
 */
.macro MATCHING_DELTAS matching
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH_B s2, s1, 7, PENDING_REFS_BYTES, 9f
    TAKE_REFS s5, s2, s6
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_previous_epoch
    mv      a0, s1
    addi    a1, sp, L
    mv      a2, s5
    call    \matching
    bnez    a0, 7f
    sd      s6, 0(s2)
    mv      a0, s1
    mv      a1, s5
    mv      a2, s2
    mv      a3, s3
    mv      a4, s4
    call    lantern_get_attestation_component_deltas
7:  LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
.endm

SPEC_FUNCTION get_source_deltas
    MATCHING_DELTAS lantern_get_matching_source_attestations
SPEC_END get_source_deltas

SPEC_FUNCTION get_target_deltas
    MATCHING_DELTAS lantern_get_matching_target_attestations
SPEC_END get_target_deltas

SPEC_FUNCTION get_head_deltas
    MATCHING_DELTAS lantern_get_matching_head_attestations
SPEC_END get_head_deltas

/*
 * s1 state, s2 scratch, s3 rewards, s4 penalties, s5 refs, s6 scratch size without the refs,
 * s7 n, s8 unslashed, s9 the earliest inclusion delay of each validator, s10 its proposer.
 * Locals: L previous epoch, L+8 total active balance, L+16 its square root, L+24 attesting list,
 * L+32 cursor, L+40 end, L+48 the attestation's ref.
 * Scratch: the refs at the end, then list 0 unslashed, 1 delays, 2 proposers, 3 attesting, then S(5).
 */
SPEC_FUNCTION get_inclusion_delay_deltas
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH_B s2, s1, 9, PENDING_REFS_BYTES, 9f
    LDQ     s7, s1, BeaconState_validators + 8
    mv      a0, s3
    mv      a1, s7
    call    zero_deltas
    mv      a0, s4
    mv      a1, s7
    call    zero_deltas
    TAKE_REFS s5, s2, s6
    SCRATCH_LIST s8, s2, s6, 0, s7
    SCRATCH_LIST s9, s2, s6, 1, s7
    SCRATCH_LIST s10, s2, s6, 2, s7
    SCRATCH_LIST t0, s2, s6, 3, s7
    sd      t0, (L + 24)(sp)
    SCRATCH_GIVE s2, s6, 4, s7
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_previous_epoch
    mv      a0, s1                          # matching_source_attestations
    addi    a1, sp, L
    mv      a2, s5
    call    lantern_get_matching_source_attestations
    bnez    a0, 7f
    mv      a0, s1
    mv      a1, s2
    addi    a2, sp, (L + 8)
    call    lantern_get_total_active_balance
    bnez    a0, 7f
    addi    a0, sp, (L + 8)
    addi    a1, sp, (L + 16)
    call    lantern_integer_squareroot
    SCRATCH_GIVE s2, s6, 4, s7
    mv      a0, s1
    mv      a1, s5
    mv      a2, s2
    mv      a3, s8
    call    lantern_get_unslashed_attesting_indices
    bnez    a0, 7f
    addi    t0, s9, LIST_FIXED              # the earliest attestation of each validator: none yet
    mv      t1, s7
    li      t2, -1
0:  beqz    t1, 1f
    sd      t2, 0(t0)
    addi    t0, t0, 8
    addi    t1, t1, -1
    j       0b
1:  addi    t0, s5, LIST_FIXED
    ld      t1, LIST_COUNT(s5)
    slli    t1, t1, 3
    add     t1, t0, t1
    sd      t0, (L + 32)(sp)
    sd      t1, (L + 40)(sp)
2:  ld      t0, (L + 32)(sp)                # in list order, so the first of the smallest delays wins, as min() does
    ld      t1, (L + 40)(sp)
    bgeu    t0, t1, 4f
    ld      t2, 0(t0)
    addi    t0, t0, 8
    sd      t0, (L + 32)(sp)
    sd      t2, (L + 48)(sp)
    SCRATCH_GIVE s2, s6, 4, s7
    mv      a0, s1
    add     a1, s1, t2
    mv      a3, s2
    ld      a4, (L + 24)(sp)
    li      a2, 0
    call    lantern_get_attesting_indices
    bnez    a0, 7f
    ld      t2, (L + 48)(sp)
    add     t2, s1, t2
    ld      t3, PendingAttestation_inclusion_delay(t2)
    ld      t4, PendingAttestation_proposer_index(t2)
    ld      t0, (L + 24)(sp)
    ld      t1, LIST_COUNT(t0)
    addi    t0, t0, LIST_FIXED
    addi    t5, s9, LIST_FIXED
    addi    t6, s10, LIST_FIXED
3:  beqz    t1, 2b
    ld      a2, 0(t0)
    addi    t0, t0, 8
    slli    a2, a2, 3
    add     a3, t5, a2
    ld      a4, 0(a3)
    bgeu    t3, a4, 31f
    sd      t3, 0(a3)
    add     a3, t6, a2
    sd      t4, 0(a3)
31: addi    t1, t1, -1
    j       3b
4:  addi    t0, s8, LIST_FIXED              # for index in get_unslashed_attesting_indices(state, matching_source_attestations)
    ld      t1, LIST_COUNT(s8)
    slli    t1, t1, 3
    add     t1, t0, t1
    PART    t2, t3, s1, BeaconState_validators
    ld      t3, (L + 16)(sp)
    addi    t4, s3, LIST_FIXED
    addi    t5, s9, LIST_FIXED
    addi    t6, s10, LIST_FIXED
5:  bgeu    t0, t1, 6f
    ld      a2, 0(t0)
    addi    t0, t0, 8
    slli    a2, a2, 3
    slli    a3, a2, 4
    add     a3, t2, a3
    ld      a3, Validator_effective_balance(a3)
    BASE_REWARD a3, a3, t3
    li      a4, PROPOSER_REWARD_QUOTIENT
    divu    a4, a3, a4                      # get_proposer_reward(state, index)
    add     a5, t6, a2                      # rewards[attestation.proposer_index] += proposer_reward
    ld      a5, 0(a5)
    slli    a5, a5, 3
    add     a5, t4, a5
    ld      a0, 0(a5)
    add     a1, a0, a4
    bltu    a1, a0, 8f
    sd      a1, 0(a5)
    sub     a3, a3, a4                      # max_attester_reward // attestation.inclusion_delay
    add     a5, t5, a2
    ld      a5, 0(a5)
    beqz    a5, 8f
    divu    a3, a3, a5
    add     a5, t4, a2
    ld      a0, 0(a5)
    add     a1, a0, a3
    bltu    a1, a0, 8f
    sd      a1, 0(a5)
    j       5b
6:  li      a0, LANTERN_OK
7:  LEAVE 64
8:  li      a0, LANTERN_INVALID_OVERFLOW
    LEAVE 64
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
SPEC_END get_inclusion_delay_deltas

/*
 * Phase0's version. s1 state, s2 scratch, s3 rewards, s4 penalties, s5 refs, s6 scratch size
 * without the refs, s7 n, s8 unslashed, s9 eligible, s10 the cursor over unslashed.
 * Locals: L previous epoch, L+8 total active balance, L+16 its square root, L+24 finality delay,
 * L+32 in leak, L+40 the end of unslashed.
 * Scratch: the refs at the end, then list 0 unslashed, 1 eligible, then S(5).
 */
SPEC_FUNCTION get_inactivity_penalty_deltas
    ENTER 48
    mv      s1, a0
    mv      s2, a2
    mv      s3, a3
    mv      s4, a4
    NEED_SCRATCH_B s2, s1, 7, PENDING_REFS_BYTES, 9f
    LDQ     s7, s1, BeaconState_validators + 8
    mv      a0, s3
    mv      a1, s7
    call    zero_deltas
    mv      a0, s4
    mv      a1, s7
    call    zero_deltas
    mv      a0, s1
    addi    a1, sp, (L + 32)
    call    lantern_is_in_inactivity_leak
    ld      t0, (L + 32)(sp)
    beqz    t0, 6f
    TAKE_REFS s5, s2, s6
    SCRATCH_LIST s8, s2, s6, 0, s7
    SCRATCH_LIST s9, s2, s6, 1, s7
    SCRATCH_GIVE s2, s6, 2, s7
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_previous_epoch
    mv      a0, s1                          # matching_target_attestations
    addi    a1, sp, L
    mv      a2, s5
    call    lantern_get_matching_target_attestations
    bnez    a0, 7f
    mv      a0, s1
    mv      a1, s5
    mv      a2, s2
    mv      a3, s8
    call    lantern_get_unslashed_attesting_indices
    bnez    a0, 7f
    SCRATCH_GIVE s2, s6, 2, s7
    mv      a0, s1
    mv      a1, s2
    addi    a2, sp, (L + 8)
    call    lantern_get_total_active_balance
    bnez    a0, 7f
    addi    a0, sp, (L + 8)
    addi    a1, sp, (L + 16)
    call    lantern_integer_squareroot
    mv      a0, s1
    mv      a1, s9
    call    lantern_get_eligible_validator_indices
    bnez    a0, 7f
    mv      a0, s1
    addi    a1, sp, (L + 24)
    call    lantern_get_finality_delay
    addi    s10, s8, LIST_FIXED             # the cursor over matching_target_attesting_indices
    ld      t0, LIST_COUNT(s8)
    slli    t0, t0, 3
    add     t0, s10, t0
    sd      t0, (L + 40)(sp)
    addi    t0, s9, LIST_FIXED              # for index in get_eligible_validator_indices(state)
    ld      t1, LIST_COUNT(s9)
    slli    t1, t1, 3
    add     t1, t0, t1
    PART    t2, t3, s1, BeaconState_validators
    ld      t3, (L + 16)(sp)
    ld      t4, (L + 24)(sp)
    li      t5, FORK_INACTIVITY_PENALTY_QUOTIENT
    addi    t6, s4, LIST_FIXED
    ld      s6, (L + 40)(sp)                # the end of unslashed: the scratch size is no longer needed
1:  bgeu    t0, t1, 6f
    ld      a2, 0(t0)
    addi    t0, t0, 8
    slli    a3, a2, 7
    add     a3, t2, a3
    ld      a3, Validator_effective_balance(a3)
    BASE_REWARD a4, a3, t3
    li      a5, PROPOSER_REWARD_QUOTIENT
    divu    a5, a4, a5
    slli    a4, a4, 2                       # BASE_REWARDS_PER_EPOCH * base_reward - get_proposer_reward(state, index)
    sub     a4, a4, a5
    slli    a5, a2, 3
    add     a5, t6, a5
    ld      a0, 0(a5)
    add     a1, a0, a4
    bltu    a1, a0, 8f
    IN_SORTED a2, s10, s6, a0
    bnez    a0, 2f
    mulhu   a0, a3, t4                      # not a target attester: effective_balance * finality_delay // INACTIVITY_PENALTY_QUOTIENT
    bnez    a0, 8f
    mul     a0, a3, t4
    divu    a0, a0, t5
    add     a4, a1, a0
    bltu    a4, a1, 8f
    mv      a1, a4
2:  sd      a1, 0(a5)
    j       1b
6:  li      a0, LANTERN_OK
7:  LEAVE 48
8:  li      a0, LANTERN_INVALID_OVERFLOW
    LEAVE 48
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END get_inactivity_penalty_deltas

/* L0: add the n entries (a2) of list a1 to those of list a0. a0 = LANTERN_OK, or LANTERN_INVALID_OVERFLOW. A leaf. */
LOCAL_FUNCTION add_deltas
    UNWIND_END_PROLOGUE
    addi    a0, a0, LIST_FIXED
    addi    a1, a1, LIST_FIXED
1:  beqz    a2, 2f
    ld      t0, 0(a0)
    ld      t1, 0(a1)
    add     t1, t0, t1
    bltu    t1, t0, 3f
    sd      t1, 0(a0)
    addi    a0, a0, 8
    addi    a1, a1, 8
    addi    a2, a2, -1
    j       1b
2:  li      a0, LANTERN_OK
    ret
3:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION add_deltas

/* Add the component's rewards and penalties to the totals. */
.macro ADD_BOTH
    mv      a0, s3
    mv      a1, s7
    mv      a2, s6
    call    add_deltas
    bnez    a0, 7f
    mv      a0, s4
    mv      a1, s8
    mv      a2, s6
    call    add_deltas
    bnez    a0, 7f
.endm

/* One component: a0 = fn(state, scratch, component rewards, component penalties). */
.macro COMPONENT fn
    sd      s5, 0(s2)
    mv      a0, s1
    mv      a1, s2
    mv      a2, s7
    mv      a3, s8
    call    \fn
    bnez    a0, 7f
.endm

/*
 * s1 state, s2 scratch, s3 rewards, s4 penalties, s5 the scratch size the components get,
 * s6 n, s7 component rewards, s8 component penalties, s9 config.
 * Scratch: list 0 component rewards, list 1 component penalties, then the components' S(9) + refs.
 */
SPEC_FUNCTION get_attestation_deltas
    ENTER 16
    mv      s1, a0
    mv      s9, a1
    mv      s2, a2
    mv      s3, a3
    mv      s4, a4
    NEED_SCRATCH_B s2, s1, 11, PENDING_REFS_BYTES, 9f
    LDQ     s6, s1, BeaconState_validators + 8
    mv      a0, s3
    mv      a1, s6
    call    zero_deltas
    mv      a0, s4
    mv      a1, s6
    call    zero_deltas
    ld      s5, 0(s2)
    SCRATCH_LIST s7, s2, s5, 0, s6
    SCRATCH_LIST s8, s2, s5, 1, s6
    SCRATCH_GIVE s2, s5, 2, s6
    ld      s5, 0(s2)
    COMPONENT lantern_get_source_deltas
    ADD_BOTH
    COMPONENT lantern_get_target_deltas
    ADD_BOTH
    COMPONENT lantern_get_head_deltas
    ADD_BOTH
    COMPONENT lantern_get_inclusion_delay_deltas
    mv      a0, s3                          # inclusion delay: rewards only
    mv      a1, s7
    mv      a2, s6
    call    add_deltas
    bnez    a0, 7f
    sd      s5, 0(s2)                       # inactivity: penalties only
    mv      a0, s1
    mv      a1, s9
    mv      a2, s2
    mv      a3, s7
    mv      a4, s8
    call    lantern_get_inactivity_penalty_deltas
    bnez    a0, 7f
    mv      a0, s4
    mv      a1, s8
    mv      a2, s6
    call    add_deltas
7:  LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_attestation_deltas

/*
 * s1 state, s2 config, s3 scratch, s4 result, s5 n, s6 rewards, s7 penalties, s8 index,
 * s9 scratch size. Locals: L epoch, L+8 index.
 * Scratch: list 0 rewards, list 1 penalties, then get_attestation_deltas's S(11) + refs.
 */
SPEC_FUNCTION process_rewards_and_penalties
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH_B s3, s1, 13, PENDING_REFS_BYTES, 9f
    sd      zero, 0(s4)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      t0, L(sp)
    beqz    t0, 6f                          # GENESIS_EPOCH is 0
    LDQ     s5, s1, BeaconState_validators + 8
    ld      s9, 0(s3)
    SCRATCH_LIST s6, s3, s9, 0, s5
    SCRATCH_LIST s7, s3, s9, 1, s5
    SCRATCH_GIVE s3, s9, 2, s5
    mv      a0, s1                          # rewards, penalties = get_attestation_deltas(state)
    mv      a1, s2
    mv      a2, s3
    mv      a3, s6
    mv      a4, s7
    call    lantern_get_attestation_deltas
    CHECK_STATUS s4, 7f, 6f
    li      s8, 0
1:  bgeu    s8, s5, 6f
    sd      s8, (L + 8)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 8)
    slli    t0, s8, 3
    add     a2, s6, t0
    addi    a2, a2, LIST_FIXED
    call    lantern_increase_balance
    mv      a0, s1
    addi    a1, sp, (L + 8)
    slli    t0, s8, 3
    add     a2, s7, t0
    addi    a2, a2, LIST_FIXED
    call    lantern_decrease_balance
    addi    s8, s8, 1
    j       1b
6:  li      a0, LANTERN_OK
7:  LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END process_rewards_and_penalties
.if GENESIS_EPOCH != 0
.error "process_rewards_and_penalties compares the epoch with 0"
.endif

/* ---------------------------------------------------------------- Justification and finalization */

/*
 * s1 state, s2 config, s3 scratch, s4 result, s5 refs, s6 scratch size without the refs.
 * Locals: L current epoch, L+8 previous epoch, L+16 total active balance, L+24 previous target
 * balance, L+32 current target balance.
 * Scratch: the refs at the end, then get_attesting_balance's S(6).
 */
SPEC_FUNCTION process_justification_and_finalization
    ENTER 48
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH_B s3, s1, 6, PENDING_REFS_BYTES, 9f
    sd      zero, 0(s4)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      t0, L(sp)
    li      t1, GENESIS_EPOCH + 1
    bleu    t0, t1, 6f
    mv      a0, s1
    addi    a1, sp, (L + 8)
    call    lantern_get_previous_epoch
    TAKE_REFS s5, s3, s6
    mv      a0, s1
    mv      a1, s3
    addi    a2, sp, (L + 16)
    call    lantern_get_total_active_balance
    bnez    a0, 7f
    mv      a0, s1                          # previous_attestations = get_matching_target_attestations(state, previous_epoch)
    addi    a1, sp, (L + 8)
    mv      a2, s5
    call    lantern_get_matching_target_attestations
    CHECK_STATUS s4, 7f, 6f
    sd      s6, 0(s3)
    mv      a0, s1
    mv      a1, s5
    mv      a2, s3
    addi    a3, sp, (L + 24)
    call    lantern_get_attesting_balance
    CHECK_STATUS s4, 7f, 6f
    mv      a0, s1                          # current_attestations
    addi    a1, sp, L
    mv      a2, s5
    call    lantern_get_matching_target_attestations
    CHECK_STATUS s4, 7f, 6f
    sd      s6, 0(s3)
    mv      a0, s1
    mv      a1, s5
    mv      a2, s3
    addi    a3, sp, (L + 32)
    call    lantern_get_attesting_balance
    CHECK_STATUS s4, 7f, 6f
    mv      a0, s1
    addi    a1, sp, (L + 16)
    addi    a2, sp, (L + 24)
    addi    a3, sp, (L + 32)
    mv      a4, s4
    call    lantern_weigh_justification_and_finalization
7:  LEAVE 48
6:  li      a0, LANTERN_OK
    LEAVE 48
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END process_justification_and_finalization

/* ---------------------------------------------------------------- Record updates */

/*
 * L0: a0 = LANTERN_OK when state a0's previous_epoch_attestations can take the current ones,
 * else LANTERN_BUFFER_TOO_SMALL. A leaf. Uses t0-t4, a7.
 */
LOCAL_FUNCTION record_room
    UNWIND_END_PROLOGUE
    LDQ     t0, a0, BeaconState_current_epoch_attestations
    LDQ     t1, a0, BeaconState_current_epoch_attestations + 8
    add     t2, a0, t0
    li      t3, 0
1:  beqz    t1, 2f
    ld      t4, 0(t2)
    add     t3, t3, t4
    add     t2, t2, t4
    addi    t1, t1, -1
    j       1b
2:  LDQ     t1, a0, BeaconState_previous_epoch_attestations
    sub     t0, t0, t1
    bltu    t0, t3, 9f
    li      a0, LANTERN_OK
    ret
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    ret
END_FUNCTION record_room

/* s1 state, s2 result. */
SPEC_FUNCTION process_participation_record_updates
    ENTER 0
    mv      s1, a0
    mv      s2, a3
    call    record_room                     # previous_epoch_attestations = current_epoch_attestations
    bnez    a0, 7f
    LDQ     t0, s1, BeaconState_current_epoch_attestations
    LDQ     t1, s1, BeaconState_current_epoch_attestations + 8
    add     a1, s1, t0
    li      a2, 0
1:  beqz    t1, 2f
    add     t2, a1, a2
    ld      t2, 0(t2)
    add     a2, a2, t2
    addi    t1, t1, -1
    j       1b
2:  LDQ     a0, s1, BeaconState_previous_epoch_attestations
    add     a0, s1, a0
    call    lantern_copy                    # the previous list starts before the current one
    LDQ     t0, s1, BeaconState_current_epoch_attestations + 8
    STQ     t0, s1, BeaconState_previous_epoch_attestations + 8
    STQ     zero, s1, BeaconState_current_epoch_attestations + 8   # current_epoch_attestations = []
    sd      zero, 0(s2)
    li      a0, LANTERN_OK
7:  LEAVE 0
SPEC_END process_participation_record_updates
