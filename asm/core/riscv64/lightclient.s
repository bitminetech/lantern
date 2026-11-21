/*
 * Light client data, RISC-V. Requirements: docs/reference/light-client.md.
 */

.if FORK >= FORK_ALTAIR
.set LCH_FIXED, 112                          # a LightClientHeader: beacon
.set LCU_BRANCH, 32 * 5                      # next_sync_committee_branch
.set LCU_FINALITY, 32 * 6                    # finality_branch
.if FORK >= FORK_ELECTRA
.set LCU_BRANCH, 32 * 6
.set LCU_FINALITY, 32 * 7
.endif
.if FORK >= FORK_CAPELLA
.set LCH_FIXED, 112 + 4 + 32 * 4             # beacon, the offset of execution, execution_branch
.set LCU_HEADER, 4                           # the headers of an update: offsets
.else
.set LCU_HEADER, LCH_FIXED
.endif
.set LCU_NEXT, LCU_HEADER + 48 * SYNC_COMMITTEE_SIZE + 48   # next_sync_committee_branch
.set LCU_FINALIZED, LCU_NEXT + LCU_BRANCH                   # finalized_header, or its offset
.set LCU_FINALITY_AT, LCU_FINALIZED + LCU_HEADER            # finality_branch
.set LCU_BITS, LCU_FINALITY_AT + LCU_FINALITY               # sync_aggregate.sync_committee_bits
.set LCU_SIGNATURE_SLOT, LCU_BITS + SYNC_COMMITTEE_SIZE / 8 + 96
.set LCU_FIXED, LCU_SIGNATURE_SLOT + 8

# dst = the little endian u64 at the address addr, of any alignment. Uses t5, t6.
.macro LC_LD64 dst, addr
    li      \dst, 0
    li      t5, 7
71: add     t6, \addr, t5
    lbu     t6, 0(t6)
    slli    \dst, \dst, 8
    or      \dst, \dst, t6
    addi    t5, t5, -1
    bgez    t5, 71b
.endm

# dst = the little endian u32 at the address addr, of any alignment. Uses t5, t6.
.macro LC_LD32 dst, addr
    li      \dst, 0
    li      t5, 3
72: add     t6, \addr, t5
    lbu     t6, 0(t6)
    slli    \dst, \dst, 8
    or      \dst, \dst, t6
    addi    t5, t5, -1
    bgez    t5, 72b
.endm

# dst = 1 when one of the n bytes at addr is not zero, else 0. Uses t3, t4, t5, t6.
.macro LC_ANY dst, addr, n
    li      \dst, 0
    mv      t3, \addr
    li      t4, \n
73: lbu     t5, 0(t3)
    or      \dst, \dst, t5
    addi    t3, t3, 1
    addi    t4, t4, -1
    bnez    t4, 73b
    snez    \dst, \dst
.endm

# The fields of the LightClientUpdate ByteList a0 that is_better_update compares: a0 = 0 with a1
# the participants, a2 attested_header.beacon.slot, a3 finalized_header.beacon.slot, a4
# signature_slot, a5 1 with a next_sync_committee_branch not all zero, a6 1 with a finality_branch
# not all zero; a0 = 1 for bytes that are no update of the fork. Uses t0-t6, a7.
LOCAL_FUNCTION lc_update_fields
    UNWIND_END_PROLOGUE
    ld      t0, 8(a0)
    add     t0, a0, t0                      # the bytes, t1 of them
    ld      t1, 16(a0)
    li      t2, LCU_FIXED
    bltu    t1, t2, 9f
.if FORK >= FORK_CAPELLA
    LC_LD32 a7, t0                          # the headers: at their offsets, the first at the fixed part
    bne     a7, t2, 9f
    li      t3, LCU_FINALIZED
    add     t3, t0, t3
    LC_LD32 a6, t3
    addi    t3, a7, LCH_FIXED
    bgtu    t3, a6, 9f
    addi    t3, a6, LCH_FIXED
    bgtu    t3, t1, 9f
    add     t3, t0, a7
    LC_LD64 a2, t3
    add     t3, t0, a6
    LC_LD64 a3, t3
.else
    LC_LD64 a2, t0
    li      t3, LCU_FINALIZED
    add     t3, t0, t3
    LC_LD64 a3, t3
.endif
    li      t3, LCU_SIGNATURE_SLOT
    add     t3, t0, t3
    LC_LD64 a4, t3
    li      t3, LCU_BITS                    # the participants
    add     t3, t0, t3
    li      t4, SYNC_COMMITTEE_SIZE / 8
    li      a1, 0
1:  lbu     t5, 0(t3)
    addi    t3, t3, 1
2:  beqz    t5, 3f
    addi    t6, t5, -1
    and     t5, t5, t6
    addi    a1, a1, 1
    j       2b
3:  addi    t4, t4, -1
    bnez    t4, 1b
    li      t2, LCU_NEXT                    # the branches: any byte not zero
    add     t2, t0, t2
    LC_ANY  a5, t2, LCU_BRANCH
    li      t2, LCU_FINALITY_AT
    add     t2, t0, t2
    LC_ANY  a6, t2, LCU_FINALITY
    li      a0, 0
    ret
9:  li      a0, 1
    ret
END_FUNCTION lc_update_fields
.endif

# dst = the sync committee period of the slot src. Uses t6.
.macro LC_PERIOD dst, src
    li      t6, SLOTS_PER_EPOCH * EPOCHS_PER_SYNC_COMMITTEE_PERIOD
    divu    \dst, \src, t6
.endm

# (new, old, out) -> a0: is_better_update of two updates (light-client.md). s1 out, s2 old; the
# fields of new: s3 participants, s4 attested slot, s5 finalized slot, s6 signature slot, s7 a sync
# committee branch, s8 a finality branch. Locals: the fields of old, in that order.
SPEC_FUNCTION is_better_update
    ENTER 48
.if FORK == FORK_PHASE0
    li      a0, LANTERN_NO_STATE_ANSWER
    LEAVE 48
.else
    mv      s1, a2
    mv      s2, a1
    call    lc_update_fields
    bnez    a0, 96f
    mv      s3, a1
    mv      s4, a2
    mv      s5, a3
    mv      s6, a4
    mv      s7, a5
    mv      s8, a6
    mv      a0, s2
    call    lc_update_fields
    bnez    a0, 96f
    sd      a1, (L + 0)(sp)
    sd      a2, (L + 8)(sp)
    sd      a3, (L + 16)(sp)
    sd      a4, (L + 24)(sp)
    sd      a5, (L + 32)(sp)
    sd      a6, (L + 40)(sp)
    li      t2, SYNC_COMMITTEE_SIZE * 2     # supermajority: participants * 3 >= SYNC_COMMITTEE_SIZE * 2
    li      t3, 3
    mul     t0, s3, t3
    sltu    t4, t0, t2
    xori    t4, t4, 1
    ld      t0, (L + 0)(sp)
    mul     t0, t0, t3
    sltu    t5, t0, t2
    xori    t5, t5, 1
    bne     t4, t5, 80f
    bnez    t4, 1f
    ld      t0, (L + 0)(sp)                 # neither: the more participants
    beq     s3, t0, 1f
    sltu    t4, t0, s3
    j       80f
1:  LC_PERIOD t0, s4                        # a relevant sync committee: a branch, and the attested and signature periods equal
    LC_PERIOD t1, s6
    sub     t0, t0, t1
    seqz    t4, t0
    and     t4, t4, s7
    ld      t2, (L + 8)(sp)
    LC_PERIOD t0, t2
    ld      t2, (L + 24)(sp)
    LC_PERIOD t1, t2
    sub     t0, t0, t1
    seqz    t5, t0
    ld      t2, (L + 32)(sp)
    and     t5, t5, t2
    bne     t4, t5, 80f
    mv      t4, s8                          # finality
    ld      t5, (L + 40)(sp)
    bne     t4, t5, 80f
    beqz    t4, 2f
    LC_PERIOD t0, s5                        # sync committee finality: the finalized and attested periods equal
    LC_PERIOD t1, s4
    sub     t0, t0, t1
    seqz    t4, t0
    ld      t2, (L + 16)(sp)
    LC_PERIOD t0, t2
    ld      t2, (L + 8)(sp)
    LC_PERIOD t1, t2
    sub     t0, t0, t1
    seqz    t5, t0
    bne     t4, t5, 80f
2:  ld      t0, (L + 0)(sp)                 # the more participants
    beq     s3, t0, 3f
    sltu    t4, t0, s3
    j       80f
3:  ld      t0, (L + 8)(sp)                 # the lower attested slot
    beq     s4, t0, 4f
    sltu    t4, s4, t0
    j       80f
4:  ld      t0, (L + 24)(sp)                # the lower signature slot
    sltu    t4, s6, t0
80: sd      t4, 0(s1)                       # the side that has it
    li      a0, LANTERN_OK
    LEAVE 48
96: li      a0, LANTERN_INVALID_ENCODING
    LEAVE 48
.endif
SPEC_END is_better_update

# (body, scratch, out) -> a0: the branch of execution_payload of a body (light-client.md). s1 body,
# s2 scratch, s3 out, s4 the body's value, s5 a Branch at the end of scratch. Locals: L the
# scratch's size on entry, L+8 the generalized index.
SPEC_FUNCTION execution_branch
    ENTER 16
.if FORK < FORK_CAPELLA
    li      a0, LANTERN_NO_STATE_ANSWER
    LEAVE 16
.else
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      t0, 0(s2)
    sd      t0, L(sp)
    ADDRESS a0, lantern_type_BeaconBlockBody
    mv      a1, s1
    mv      a2, s2
    call    node_decode
    li      t0, 1
    beq     a0, t0, 99f
    bnez    a0, 96f
    mv      s4, a1
    ld      t0, 0(s2)
    li      t1, 24 + 8 * 32
    bltu    t0, t1, 99f
    sub     t0, t0, t1
    andi    t0, t0, -8
    sd      t0, 0(s2)
    add     s5, s2, t0
    sd      t1, 0(s5)
    li      t2, 24
    sd      t2, 8(s5)
    sd      zero, 16(s5)
    li      t0, EXECUTION_PAYLOAD_GINDEX
    sd      t0, (L + 8)(sp)
    ADDRESS a0, lantern_type_BeaconBlockBody
    mv      a1, s4
    addi    a2, sp, L + 8
    mv      a3, s2
    mv      a4, s5
    CALL_GLOBAL ssz_build_proof
    li      t0, SSZ_BUFFER_TOO_SMALL
    beq     a0, t0, 99f
    bnez    a0, 96f
    ld      a2, 16(s5)
    slli    a2, a2, 5
    addi    a1, s5, 24
    mv      a0, s3
    call    lantern_copy
    ld      t0, L(sp)
    sd      t0, 0(s2)
    li      a0, LANTERN_OK
    LEAVE 16
96: ld      t0, L(sp)
    sd      t0, 0(s2)
    li      a0, LANTERN_INVALID_ENCODING
    LEAVE 16
99: ld      t0, L(sp)
    sd      t0, 0(s2)
    li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
.endif
SPEC_END execution_branch

.set LC_EPH_EXTRA, 436                       # an ExecutionPayloadHeader's SSZ bytes: the offset of extra_data
.set LC_EPH_CAPELLA, 568                     # the fixed part of capella's
.set LC_EPH_DENEB, 584                       # of deneb's, electra's and fulu's: blob_gas_used, excess_blob_gas
.set LC_EPH_FIXED, LC_EPH_CAPELLA
.if FORK >= FORK_DENEB
.set LC_EPH_FIXED, LC_EPH_DENEB
.endif
.set LC_HEADER_EXECUTION, 112 + 4 + 32 * 4   # a LightClientHeader from capella: where execution starts
.set LC_BODY_PAYLOAD, 220 + SYNC_COMMITTEE_SIZE / 8 + 96   # a BlindedBeaconBlockBody's SSZ bytes: the offset of execution_payload_header

# (block, scratch, out) -> a0: block_to_light_client_header of the block (light-client.md). s1
# block, s2 scratch, s3 out, s4 the message, s5 the body, s6 a Branch or the blinded block at the
# end of scratch, s7 the bytes of out, s8 the header's bytes, s9 the scratch's size on entry, s10
# the size after the decoded block. Locals: L the generalized index.
SPEC_FUNCTION block_to_light_client_header
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s9, 0(s2)
    ld      t0, 0(s3)                       # out: room for the beacon header; from capella, the branch and a payload header too
    li      t1, 24 + 112
.if FORK >= FORK_CAPELLA
    li      t1, 24 + LC_HEADER_EXECUTION + LC_EPH_FIXED
.endif
    bltu    t0, t1, 98f
    ADDRESS a0, lantern_type_SignedBeaconBlock
    mv      a1, s1
    mv      a2, s2
    call    node_decode
    li      t0, 1
    beq     a0, t0, 98f
    bnez    a0, 96f
    PART    s4, t0, a1, SignedBeaconBlock_message
    PART    s5, t0, s4, BeaconBlock_body
    ld      s10, 0(s2)
    addi    s7, s3, 24
    li      t0, 24
    sd      t0, 8(s3)
    LDQ     t0, s4, BeaconBlock_slot        # beacon
    sd      t0, 0(s7)
    LDQ     t0, s4, BeaconBlock_proposer_index
    sd      t0, 8(s7)
    addi    t0, s7, 16
    ADDQ    t1, s4, BeaconBlock_parent_root
    COPY32  t0, t1
    addi    t0, s7, 48
    ADDQ    t1, s4, BeaconBlock_state_root
    COPY32  t0, t1
    ADDRESS a0, lantern_type_BeaconBlockBody
    mv      a1, s5
    mv      a2, s2
    addi    a3, s7, 80
    CALL_GLOBAL ssz_hash_tree_root
    li      t0, SSZ_BUFFER_TOO_SMALL
    beq     a0, t0, 98f
    bnez    a0, 96f
    li      s8, 112
.if FORK >= FORK_CAPELLA
    li      t1, 24 + 8 * 32                 # execution_branch: ssz_build_proof of the body at 25
    bltu    s10, t1, 98f
    sub     t0, s10, t1
    andi    t0, t0, -8
    sd      t0, 0(s2)
    add     s6, s2, t0
    sd      t1, 0(s6)
    li      t2, 24
    sd      t2, 8(s6)
    sd      zero, 16(s6)
    li      t0, EXECUTION_PAYLOAD_GINDEX
    sd      t0, L(sp)
    ADDRESS a0, lantern_type_BeaconBlockBody
    mv      a1, s5
    addi    a2, sp, L
    mv      a3, s2
    mv      a4, s6
    CALL_GLOBAL ssz_build_proof
    sd      s10, 0(s2)
    li      t0, SSZ_BUFFER_TOO_SMALL
    beq     a0, t0, 98f
    bnez    a0, 96f
    addi    a0, s7, 116
    addi    a1, s6, 24
    li      a2, 128
    call    lantern_copy
    li      t0, LC_HEADER_EXECUTION
    sw      t0, 112(s7)
    ld      t0, 16(s1)                      # execution: of the blinded block, at the end of scratch
    addi    t0, t0, 24 + 1024 + 7
    andi    t0, t0, -8
    bltu    s10, t0, 98f
    sub     t1, s10, t0
    sd      t1, 0(s2)
    add     s6, s2, t1
    sd      t0, 0(s6)
    li      t2, 24
    sd      t2, 8(s6)
    sd      zero, 16(s6)
    mv      a0, s1
    mv      a1, s2
    mv      a2, s6
    call    lantern_node_blinded_block
    sd      s10, 0(s2)
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 98f
    bnez    a0, 96f
    ld      t0, 8(s6)                       # its bytes: the message, the body, the header's offsets
    add     t0, s6, t0
    lwu     t1, 0(t0)
    add     t0, t0, t1
    lwu     t1, 80(t0)
    add     t0, t0, t1
    li      t1, LC_BODY_PAYLOAD
    add     t1, t0, t1
    lwu     t2, 0(t1)
    lwu     t3, 4(t1)
    sub     a2, t3, t2
    add     a1, t0, t2
    ld      t0, 0(s3)                       # out: room for it too; at least LC_EPH_FIXED, as checked first
    addi    t0, t0, -(24 + LC_HEADER_EXECUTION)
    bgtu    a2, t0, 98f
    addi    s8, a2, LC_HEADER_EXECUTION
    addi    a0, s7, LC_HEADER_EXECUTION
    call    lantern_copy
.endif
    sd      s8, 16(s3)
    sd      s9, 0(s2)
    li      a0, LANTERN_OK
    LEAVE 16
96: sd      s9, 0(s2)
    li      a0, LANTERN_INVALID_ENCODING
    LEAVE 16
98: sd      s9, 0(s2)
    li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END block_to_light_client_header

# (header, from, out) -> a0: the header of the fork from as one of the fork (light-client.md). s1
# the header's bytes, s2 their count, s3 from, s4 out, s5 the bytes of out, s6 the room of out.
SPEC_FUNCTION upgrade_lc_header
    ENTER 0
    li      t0, FORK
    bgtu    a1, t0, 97f
    ld      t0, 8(a0)
    add     s1, a0, t0
    ld      s2, 16(a0)
    mv      s3, a1
    mv      s4, a2
    addi    s5, s4, 24
    ld      s6, 0(s4)
    addi    s6, s6, -24                     # the room of out
.if FORK >= FORK_CAPELLA
    li      t0, FORK_CAPELLA
    bgeu    s3, t0, 2f
.endif
    li      t0, 112                         # before capella: beacon
    bne     s2, t0, 96f
.if FORK >= FORK_CAPELLA
    li      t0, LC_HEADER_EXECUTION + LC_EPH_FIXED  # to capella or later: an empty payload header and a zero branch
    bltu    s6, t0, 98f
    mv      a0, s5
    mv      a1, t0
    call    lantern_zero
    mv      a0, s5
    mv      a1, s1
    li      a2, 112
    call    lantern_copy
    li      t0, LC_HEADER_EXECUTION
    sw      t0, 112(s5)
    li      t0, LC_EPH_FIXED
    li      t1, LC_HEADER_EXECUTION + LC_EPH_EXTRA
    add     t1, s5, t1
    sw      t0, 0(t1)
    li      s2, LC_HEADER_EXECUTION + LC_EPH_FIXED
    j       8f
2:  lwu     t0, 112(s1)                     # capella or later: its payload header at 244, extra_data after the fixed part
    li      t1, LC_HEADER_EXECUTION
    bne     t0, t1, 96f
    li      t2, LC_EPH_DENEB
    li      t0, FORK_CAPELLA
    bne     s3, t0, 3f
    li      t2, LC_EPH_CAPELLA
3:  addi    t0, t2, LC_HEADER_EXECUTION
    bltu    s2, t0, 96f
    li      t1, LC_HEADER_EXECUTION + LC_EPH_EXTRA
    add     t1, s1, t1
    lwu     t1, 0(t1)
    bne     t1, t2, 96f
.if FORK >= FORK_DENEB
    li      t0, FORK_CAPELLA                # capella to deneb or later: blob_gas_used and excess_blob_gas 0
    bne     s3, t0, 7f
    addi    t0, s2, 16
    bltu    s6, t0, 98f
    mv      a0, s5
    mv      a1, s1
    li      a2, LC_HEADER_EXECUTION + LC_EPH_CAPELLA
    call    lantern_copy
    li      t0, LC_HEADER_EXECUTION + LC_EPH_CAPELLA
    add     t1, s5, t0
    sd      zero, 0(t1)
    sd      zero, 8(t1)
    addi    a0, t1, 16
    add     a1, s1, t0
    sub     a2, s2, t0
    call    lantern_copy
    li      t0, LC_EPH_DENEB
    li      t1, LC_HEADER_EXECUTION + LC_EPH_EXTRA
    add     t1, s5, t1
    sw      t0, 0(t1)
    addi    s2, s2, 16
    j       8f
.endif
.endif
7:  bltu    s6, s2, 98f                     # the same layout: the same bytes
    mv      a0, s5
    mv      a1, s1
    mv      a2, s2
    call    lantern_copy
8:  li      t0, 24
    sd      t0, 8(s4)
    sd      s2, 16(s4)
    li      a0, LANTERN_OK
    LEAVE 0
96: li      a0, LANTERN_INVALID_ENCODING
    LEAVE 0
97: li      a0, LANTERN_INVALID_EVENT
    LEAVE 0
98: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END upgrade_lc_header
