/*
 * Light client data, ARM64. Requirements: docs/reference/light-client.md.
 */

.if FORK >= FORK_ALTAIR
.set LCH_FIXED, 112                          /* a LightClientHeader: beacon */
.set LCU_BRANCH, 32 * 5                      /* next_sync_committee_branch */
.set LCU_FINALITY, 32 * 6                    /* finality_branch */
.if FORK >= FORK_ELECTRA
.set LCU_BRANCH, 32 * 6
.set LCU_FINALITY, 32 * 7
.endif
.if FORK >= FORK_CAPELLA
.set LCH_FIXED, 112 + 4 + 32 * 4             /* beacon, the offset of execution, execution_branch */
.set LCU_HEADER, 4                           /* the headers of an update: offsets */
.else
.set LCU_HEADER, LCH_FIXED
.endif
.set LCU_NEXT, LCU_HEADER + 48 * SYNC_COMMITTEE_SIZE + 48   /* next_sync_committee_branch */
.set LCU_FINALIZED, LCU_NEXT + LCU_BRANCH                   /* finalized_header, or its offset */
.set LCU_FINALITY_AT, LCU_FINALIZED + LCU_HEADER            /* finality_branch */
.set LCU_BITS, LCU_FINALITY_AT + LCU_FINALITY               /* sync_aggregate.sync_committee_bits */
.set LCU_SIGNATURE_SLOT, LCU_BITS + SYNC_COMMITTEE_SIZE / 8 + 96
.set LCU_FIXED, LCU_SIGNATURE_SLOT + 8
.endif

/*
 * L0: the fields of the LightClientUpdate ByteList x0 that is_better_update compares: x0 = 0 with
 * x1 the participants, x2 attested_header.beacon.slot, x3 finalized_header.beacon.slot, x4
 * signature_slot, x5 1 with a next_sync_committee_branch not all zero, x6 1 with a finality_branch
 * not all zero; x0 = 1 for bytes that are no update of the fork. Uses x7-x15.
 */
.if FORK >= FORK_ALTAIR
LOCAL_FUNCTION lc_update_fields
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #8]
    add     x7, x0, x9                      /* the bytes, x8 of them */
    ldr     x8, [x0, #16]
    MOVQ    x9, LCU_FIXED
    cmp     x8, x9
    b.lo    9f
.if FORK >= FORK_CAPELLA
    ldr     w10, [x7]                       /* the headers: at their offsets, the first at the fixed part */
    MOVQ    x11, LCU_FINALIZED
    ldr     w11, [x7, x11]
    cmp     x10, x9
    b.ne    9f
    add     x12, x10, #LCH_FIXED
    cmp     x12, x11
    b.hi    9f
    add     x12, x11, #LCH_FIXED
    cmp     x12, x8
    b.hi    9f
    ldr     x2, [x7, x10]
    ldr     x3, [x7, x11]
.else
    ldr     x2, [x7]
    MOVQ    x11, LCU_FINALIZED
    ldr     x3, [x7, x11]
.endif
    MOVQ    x11, LCU_SIGNATURE_SLOT
    ldr     x4, [x7, x11]
    MOVQ    x11, LCU_BITS                   /* the participants */
    add     x11, x7, x11
    mov     x12, #(SYNC_COMMITTEE_SIZE / 8)
    mov     x1, #0
1:  ldrb    w13, [x11], #1
    fmov    s0, w13
    cnt     v0.8b, v0.8b
    umov    w13, v0.b[0]
    add     x1, x1, x13
    subs    x12, x12, #1
    b.ne    1b
    MOVQ    x11, LCU_NEXT                   /* the branches: any byte not zero */
    add     x11, x7, x11
    mov     x12, #(LCU_BRANCH / 8)
    mov     x13, #0
2:  ldr     x14, [x11], #8
    orr     x13, x13, x14
    subs    x12, x12, #1
    b.ne    2b
    cmp     x13, #0
    cset    x5, ne
    MOVQ    x11, LCU_FINALITY_AT
    add     x11, x7, x11
    mov     x12, #(LCU_FINALITY / 8)
    mov     x13, #0
3:  ldr     x14, [x11], #8
    orr     x13, x13, x14
    subs    x12, x12, #1
    b.ne    3b
    cmp     x13, #0
    cset    x6, ne
    mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION lc_update_fields
.endif

/* L0: x9 = the sync committee period of the slot x9. Uses x10. */
.macro LC_PERIOD
    MOVQ    x10, SLOTS_PER_EPOCH * EPOCHS_PER_SYNC_COMMITTEE_PERIOD
    udiv    x9, x9, x10
.endm

/*
 * (new, old, out) -> status: is_better_update of two updates (light-client.md). x19 out, x20-x25
 * the fields of new (participants, attested slot, finalized slot, signature slot, a sync committee
 * branch, a finality branch), x26 old.
 */
SPEC_FUNCTION is_better_update
    ENTER 64
.if FORK == FORK_PHASE0
    mov     x0, #LANTERN_NO_STATE_ANSWER
    LEAVE 64
.else
    mov     x19, x2
    mov     x26, x1
    bl      lc_update_fields
    cbnz    x0, 96f
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    mov     x25, x6
    mov     x0, x26
    bl      lc_update_fields
    cbnz    x0, 96f
    stp     x1, x2, [sp, #L]                /* old: L participants, L+8 attested, L+16 finalized, L+24 signature, L+32, L+40 the branches */
    stp     x3, x4, [sp, #(L + 16)]
    stp     x5, x6, [sp, #(L + 32)]
    mov     x11, #(SYNC_COMMITTEE_SIZE * 2) /* supermajority: participants * 3 >= SYNC_COMMITTEE_SIZE * 2 */
    mov     x12, #3
    mul     x13, x20, x12
    cmp     x13, x11
    cset    x14, hs                         /* new */
    ldr     x13, [sp, #L]
    mul     x13, x13, x12
    cmp     x13, x11
    cset    x15, hs                         /* old */
    cmp     x14, x15
    b.ne    80f                             /* the one with supermajority */
    cbnz    x14, 1f
    ldr     x13, [sp, #L]                   /* neither: the more participants */
    cmp     x20, x13
    b.ne    81f
1:  mov     x9, x21                         /* a relevant sync committee: a branch, and the attested and signature periods equal */
    LC_PERIOD
    mov     x11, x9
    mov     x9, x23
    LC_PERIOD
    cmp     x11, x9
    cset    x14, eq
    and     x14, x14, x24                   /* new */
    ldr     x9, [sp, #(L + 8)]
    LC_PERIOD
    mov     x11, x9
    ldr     x9, [sp, #(L + 24)]
    LC_PERIOD
    cmp     x11, x9
    cset    x15, eq
    ldr     x9, [sp, #(L + 32)]
    and     x15, x15, x9                    /* old */
    cmp     x14, x15
    b.ne    80f
    ldr     x15, [sp, #(L + 40)]            /* finality */
    mov     x14, x25
    cmp     x14, x15
    b.ne    80f
    cbz     x14, 2f
    mov     x9, x22                         /* sync committee finality: the finalized and attested periods equal */
    LC_PERIOD
    mov     x11, x9
    mov     x9, x21
    LC_PERIOD
    cmp     x11, x9
    cset    x14, eq
    ldr     x9, [sp, #(L + 16)]
    LC_PERIOD
    mov     x11, x9
    ldr     x9, [sp, #(L + 8)]
    LC_PERIOD
    cmp     x11, x9
    cset    x15, eq
    cmp     x14, x15
    b.ne    80f
2:  ldr     x13, [sp, #L]                   /* the more participants */
    cmp     x20, x13
    b.ne    81f
    ldr     x13, [sp, #(L + 8)]             /* the lower attested slot */
    cmp     x21, x13
    b.ne    82f
    ldr     x13, [sp, #(L + 24)]            /* the lower signature slot */
    cmp     x23, x13
82: cset    x9, lo
    b       85f
81: cset    x9, hi
    b       85f
80: mov     x9, x14                         /* the side that has it */
85: str     x9, [x19]
    mov     x0, #LANTERN_OK
    LEAVE 64
96: mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 64
.endif
SPEC_END is_better_update

/*
 * (body, scratch, out) -> status: the branch of execution_payload of a body (light-client.md). x19
 * body, x20 scratch, x21 out, x22 the body's value, x23 a Branch at the end of scratch, x27 the
 * scratch's size on entry. Locals: L the generalized index.
 */
SPEC_FUNCTION execution_branch
    ENTER 16
.if FORK < FORK_CAPELLA
    mov     x0, #LANTERN_NO_STATE_ANSWER
    LEAVE 16
.else
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x27, [x20]
    ADDRESS x0, lantern_type_BeaconBlockBody
    mov     x1, x19
    mov     x2, x20
    bl      node_decode
    cmp     x0, #1
    b.eq    99f
    cbnz    x0, 96f
    mov     x22, x1
    ldr     x9, [x20]
    subs    x9, x9, #(24 + 8 * 32)
    b.lo    99f
    str     x9, [x20]
    add     x23, x20, x9
    mov     x10, #(24 + 8 * 32)
    mov     x11, #24
    stp     x10, x11, [x23]
    str     xzr, [x23, #16]
    mov     x9, #EXECUTION_PAYLOAD_GINDEX
    str     x9, [sp, #L]
    ADDRESS x0, lantern_type_BeaconBlockBody
    mov     x1, x22
    add     x2, sp, #L
    mov     x3, x20
    mov     x4, x23
    CALL_GLOBAL ssz_build_proof
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    99f
    cbnz    x0, 96f
    ldr     x2, [x23, #16]
    lsl     x2, x2, #5
    add     x1, x23, #24
    mov     x0, x21
    bl      lantern_copy
    str     x27, [x20]
    mov     x0, #LANTERN_OK
    LEAVE 16
96: str     x27, [x20]
    mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 16
99: str     x27, [x20]
    mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
.endif
SPEC_END execution_branch

.set LC_EPH_EXTRA, 436                       /* an ExecutionPayloadHeader's SSZ bytes: the offset of extra_data */
.set LC_EPH_CAPELLA, 568                     /* the fixed part of capella's */
.set LC_EPH_DENEB, 584                       /* of deneb's, electra's and fulu's: blob_gas_used, excess_blob_gas */
.set LC_EPH_FIXED, LC_EPH_CAPELLA
.if FORK >= FORK_DENEB
.set LC_EPH_FIXED, LC_EPH_DENEB
.endif
.set LC_HEADER_EXECUTION, 112 + 4 + 32 * 4   /* a LightClientHeader from capella: where execution starts */
.set LC_BODY_PAYLOAD, 220 + SYNC_COMMITTEE_SIZE / 8 + 96   /* a BlindedBeaconBlockBody's SSZ bytes: the offset of execution_payload_header */

/*
 * (block, scratch, out) -> status: block_to_light_client_header of the block (light-client.md). x19
 * block, x20 scratch, x21 out, x22 the message, x23 the body, x24 a Branch or the blinded block at
 * the end of scratch, x25 the bytes of out, x27 the scratch's size on entry, x28 the size after the
 * decoded block. Locals: L the generalized index.
 */
SPEC_FUNCTION block_to_light_client_header
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x27, [x20]
    ldr     x9, [x21]                       /* out: room for the beacon header; from capella, the branch and a payload header too */
    sub     x9, x9, #24
    MOVQ    x10, 112
.if FORK >= FORK_CAPELLA
    MOVQ    x10, LC_HEADER_EXECUTION + LC_EPH_FIXED
.endif
    cmp     x9, x10
    b.lo    98f
    ADDRESS x0, lantern_type_SignedBeaconBlock
    mov     x1, x19
    mov     x2, x20
    bl      node_decode
    cmp     x0, #1
    b.eq    98f
    cbnz    x0, 96f
    PART    x22, x9, x1, SignedBeaconBlock_message
    PART    x23, x9, x22, BeaconBlock_body
    ldr     x28, [x20]
    add     x25, x21, #24
    mov     x9, #24
    str     x9, [x21, #8]
    ldr     x9, [x22, #BeaconBlock_slot]    /* beacon */
    str     x9, [x25]
    ldr     x9, [x22, #BeaconBlock_proposer_index]
    str     x9, [x25, #8]
    add     x9, x25, #16
    add     x10, x22, #BeaconBlock_parent_root
    COPY32  x9, x10
    add     x9, x25, #48
    add     x10, x22, #BeaconBlock_state_root
    COPY32  x9, x10
    ADDRESS x0, lantern_type_BeaconBlockBody
    mov     x1, x23
    mov     x2, x20
    add     x3, x25, #80
    CALL_GLOBAL ssz_hash_tree_root
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    98f
    cbnz    x0, 96f
    mov     x26, #112
.if FORK >= FORK_CAPELLA
    subs    x9, x28, #(24 + 8 * 32)         /* execution_branch: ssz_build_proof of the body at 25 */
    b.lo    98f
    str     x9, [x20]
    add     x24, x20, x9
    mov     x10, #(24 + 8 * 32)
    mov     x11, #24
    stp     x10, x11, [x24]
    str     xzr, [x24, #16]
    mov     x9, #EXECUTION_PAYLOAD_GINDEX
    str     x9, [sp, #L]
    ADDRESS x0, lantern_type_BeaconBlockBody
    mov     x1, x23
    add     x2, sp, #L
    mov     x3, x20
    mov     x4, x24
    CALL_GLOBAL ssz_build_proof
    str     x28, [x20]
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    98f
    cbnz    x0, 96f
    add     x0, x25, #116
    add     x1, x24, #24
    mov     x2, #128
    bl      lantern_copy
    mov     w9, #LC_HEADER_EXECUTION
    str     w9, [x25, #112]
    ldr     x9, [x19, #16]                  /* execution: of the blinded block, at the end of scratch */
    add     x9, x9, #(24 + 1024 + 7)
    and     x9, x9, #~7
    subs    x10, x28, x9
    b.lo    98f
    str     x10, [x20]
    add     x24, x20, x10
    mov     x11, #24
    stp     x9, x11, [x24]
    str     xzr, [x24, #16]
    mov     x0, x19
    mov     x1, x20
    mov     x2, x24
    bl      lantern_node_blinded_block
    str     x28, [x20]
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    98f
    cbnz    x0, 96f
    ldr     x9, [x24, #8]                   /* its bytes: the message, the body, the header's offsets */
    add     x9, x24, x9
    ldr     w10, [x9]
    add     x9, x9, x10
    ldr     w10, [x9, #80]
    add     x9, x9, x10
    MOVQ    x12, LC_BODY_PAYLOAD
    ldr     w10, [x9, x12]
    add     x12, x12, #4
    ldr     w11, [x9, x12]
    sub     x2, x11, x10
    add     x1, x9, x10
    ldr     x9, [x21]                       /* out: room for it too */
    sub     x9, x9, #(24 + LC_HEADER_EXECUTION)
    cmp     x2, x9
    b.hi    98f                             /* x9 is at least LC_EPH_FIXED: the room was checked first */
    add     x26, x2, #LC_HEADER_EXECUTION
    add     x0, x25, #LC_HEADER_EXECUTION
    bl      lantern_copy
.endif
    str     x26, [x21, #16]
    str     x27, [x20]
    mov     x0, #LANTERN_OK
    LEAVE 16
96: str     x27, [x20]
    mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 16
98: str     x27, [x20]
    mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END block_to_light_client_header

/*
 * (header, from, out) -> status: the header of the fork from as one of the fork (light-client.md).
 * x19 the header's bytes, x20 their count, x21 from, x22 out, x23 the bytes of out. Locals: none.
 */
SPEC_FUNCTION upgrade_lc_header
    ENTER 0
    cmp     x1, #FORK
    b.hi    97f
    ldr     x9, [x0, #8]
    add     x19, x0, x9
    ldr     x20, [x0, #16]
    mov     x21, x1
    mov     x22, x2
    add     x23, x22, #24
    ldr     x9, [x22]
    sub     x9, x9, #24                     /* the room of out */
.if FORK >= FORK_CAPELLA
    cmp     x21, #FORK_CAPELLA
    b.hs    2f
.endif
    cmp     x20, #112                       /* before capella: beacon */
    b.ne    96f
.if FORK >= FORK_CAPELLA
    MOVQ    x10, LC_HEADER_EXECUTION + LC_EPH_FIXED /* to capella or later: an empty payload header and a zero branch */
    cmp     x9, x10
    b.lo    98f
    mov     x0, x23
    mov     x1, x10
    bl      lantern_zero
    mov     x0, x23
    mov     x1, x19
    mov     x2, #112
    bl      lantern_copy
    mov     w9, #LC_HEADER_EXECUTION
    str     w9, [x23, #112]
    MOVQ    x9, LC_HEADER_EXECUTION + LC_EPH_EXTRA
    mov     w10, #LC_EPH_FIXED
    str     w10, [x23, x9]
    MOVQ    x20, LC_HEADER_EXECUTION + LC_EPH_FIXED
    b       8f
2:  ldr     w10, [x19, #112]                /* capella or later: its payload header at 244, extra_data after the fixed part */
    cmp     x10, #LC_HEADER_EXECUTION
    b.ne    96f
    MOVQ    x11, LC_EPH_DENEB
    cmp     x21, #FORK_CAPELLA
    b.ne    3f
    MOVQ    x11, LC_EPH_CAPELLA
3:  add     x12, x11, #LC_HEADER_EXECUTION
    cmp     x20, x12
    b.lo    96f
    MOVQ    x12, LC_HEADER_EXECUTION + LC_EPH_EXTRA
    ldr     w12, [x19, x12]
    cmp     x12, x11
    b.ne    96f
.if FORK >= FORK_DENEB
    cmp     x21, #FORK_CAPELLA              /* capella to deneb or later: blob_gas_used and excess_blob_gas 0 */
    b.ne    7f
    add     x10, x20, #16
    cmp     x9, x10
    b.lo    98f
    MOVQ    x2, LC_HEADER_EXECUTION + LC_EPH_CAPELLA
    mov     x0, x23
    mov     x1, x19
    bl      lantern_copy
    MOVQ    x9, LC_HEADER_EXECUTION + LC_EPH_CAPELLA
    add     x9, x23, x9
    stp     xzr, xzr, [x9]
    add     x0, x9, #16
    MOVQ    x10, LC_HEADER_EXECUTION + LC_EPH_CAPELLA
    add     x1, x19, x10
    sub     x2, x20, x10
    bl      lantern_copy
    MOVQ    x9, LC_HEADER_EXECUTION + LC_EPH_EXTRA
    mov     w10, #LC_EPH_DENEB
    str     w10, [x23, x9]
    add     x20, x20, #16
    b       8f
.endif
.endif
7:  cmp     x9, x20                         /* the same layout: the same bytes */
    b.lo    98f
    mov     x0, x23
    mov     x1, x19
    mov     x2, x20
    bl      lantern_copy
8:  mov     x9, #24
    stp     x9, x20, [x22, #8]
    mov     x0, #LANTERN_OK
    LEAVE 0
96: mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 0
97: mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 0
98: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END upgrade_lc_header

/* The offsets that the LcStore functions of the common object read in a state of any fork. */
.if BeaconState_finalized_checkpoint != NODE_STATE_FINALIZED
.error "NODE_STATE_FINALIZED is not BeaconState.finalized_checkpoint"
.endif
.if FORK >= FORK_ALTAIR
.if (BeaconState_current_sync_committee != NODE_STATE_CURRENT_SYNC_COMMITTEE) || (BeaconState_next_sync_committee != NODE_STATE_NEXT_SYNC_COMMITTEE) || (SyncCommittee__mem != LC_COMMITTEE)
.error "NODE_STATE_*_SYNC_COMMITTEE or LC_COMMITTEE is not the state's"
.endif
.endif

/*
 * (kind, parts, out) -> status: the SSZ bytes of a light client object of the fork from its parts
 * (light-client.md). x19 parts, x20 out, x21 the kind's fields (LCO_*, 3 bits each), x22 the bytes
 * of the fixed part, x23 of the variable part, x24 the fixed cursor, x25 the variable cursor, x26
 * the bytes of out, x27 and x28 a branch's bytes and roots. Locals: none.
 */
SPEC_FUNCTION lc_object
    ENTER 0
.if FORK == FORK_PHASE0
    mov     x0, #LANTERN_NO_STATE_ANSWER
    LEAVE 0
.else
    mov     x19, x1
    mov     x20, x2
    MOVQ    x21, LCO_BOOTSTRAP_FIELDS
    cbz     x0, 1f
    MOVQ    x21, LCO_UPDATE_FIELDS
    cmp     x0, #LC_OBJECT_UPDATE
    b.eq    1f
    MOVQ    x21, LCO_FINALITY_FIELDS
    cmp     x0, #LC_OBJECT_FINALITY_UPDATE
    b.eq    1f
    MOVQ    x21, LCO_OPTIMISTIC_FIELDS
    cmp     x0, #LC_OBJECT_OPTIMISTIC_UPDATE
    b.ne    97f
1:  mov     x22, #0                         /* the sizes, and the checks, before any write */
    mov     x23, #0
    mov     x9, x21
2:  and     x10, x9, #7
    cbz     x10, 5f
    lsr     x9, x9, #3
    cmp     x10, #LCO_HEADER
    b.eq    3f
    cmp     x10, #LCO_FINALIZED
    b.eq    31f
    cmp     x10, #LCO_COMMITTEE
    b.ne    21f
    ADDQ    x22, x22, LC_COMMITTEE
    b       2b
21: cmp     x10, #LCO_BRANCH
    b.ne    22f
    ldr     x11, [x19, #LcParts_branch_count]
    cmp     x11, #(LCU_BRANCH / 32)
    b.hi    97f
    add     x22, x22, #LCU_BRANCH
    b       2b
22: cmp     x10, #LCO_FINALITY
    b.ne    23f
    ldr     x11, [x19, #LcParts_finality_count]
    cmp     x11, #(LCU_FINALITY / 32)
    b.hi    97f
    add     x22, x22, #LCU_FINALITY
    b       2b
23: cmp     x10, #LCO_AGGREGATE
    b.ne    24f
    add     x22, x22, #LC_AGGREGATE
    b       2b
24: add     x22, x22, #8                    /* signature_slot */
    b       2b
3:  ldr     x11, [x19, #LcParts_header]
    b       4f
31: ldr     x11, [x19, #LcParts_finalized_header]
4:  ldr     x12, [x11, #16]                 /* a header: x12 bytes at x13 */
    ldr     x13, [x11, #8]
    add     x13, x11, x13
.if FORK >= FORK_CAPELLA
    MOVQ    x14, LC_HEADER_EXECUTION + LC_EPH_FIXED
    cmp     x12, x14
    b.lo    96f
    ldr     w14, [x13, #112]
    cmp     x14, #LC_HEADER_EXECUTION
    b.ne    96f
    add     x22, x22, #4
    add     x23, x23, x12
.else
    cmp     x12, #112
    b.ne    96f
    add     x22, x22, #112
.endif
    b       2b
5:  ldr     x9, [x20]                       /* out: room for both parts */
    sub     x9, x9, #24
    add     x10, x22, x23
    cmp     x10, x9
    b.hi    98f
    add     x26, x20, #24
    mov     x24, x26
    add     x25, x26, x22
6:  and     x10, x21, #7                    /* each field in turn */
    cbz     x10, 9f
    lsr     x21, x21, #3
    cmp     x10, #LCO_HEADER
    b.eq    7f
    cmp     x10, #LCO_FINALIZED
    b.eq    71f
    cmp     x10, #LCO_COMMITTEE
    b.ne    61f
    mov     x0, x24
    ldr     x1, [x19, #LcParts_sync_committee]
    MOVQ    x2, LC_COMMITTEE
    add     x24, x24, x2
    bl      lantern_copy
    b       6b
61: cmp     x10, #LCO_BRANCH
    b.ne    62f
    ldr     x28, [x19, #LcParts_branch]
    ldr     x27, [x19, #LcParts_branch_count]
    mov     x9, #(LCU_BRANCH / 32)
    b       63f
62: cmp     x10, #LCO_FINALITY
    b.ne    64f
    ldr     x28, [x19, #LcParts_finality_branch]
    ldr     x27, [x19, #LcParts_finality_count]
    mov     x9, #(LCU_FINALITY / 32)
63: sub     x1, x9, x27                     /* normalize_merkle_branch: zero roots first */
    lsl     x1, x1, #5
    mov     x0, x24
    add     x24, x24, x1
    bl      lantern_zero
    lsl     x2, x27, #5
    mov     x0, x24
    mov     x1, x28
    add     x24, x24, x2
    bl      lantern_copy
    b       6b
64: cmp     x10, #LCO_AGGREGATE
    b.ne    65f
    mov     x0, x24
    ldr     x1, [x19, #LcParts_sync_aggregate]
    mov     x2, #LC_AGGREGATE
    add     x24, x24, x2
    bl      lantern_copy
    b       6b
65: ldr     x9, [x19, #LcParts_signature_slot]
    str     x9, [x24], #8
    b       6b
7:  ldr     x11, [x19, #LcParts_header]
    b       8f
71: ldr     x11, [x19, #LcParts_finalized_header]
8:  ldr     x2, [x11, #16]
    ldr     x1, [x11, #8]
    add     x1, x11, x1
.if FORK >= FORK_CAPELLA
    sub     x9, x25, x26                    /* its offset, then its bytes after the fixed part */
    str     w9, [x24], #4
    mov     x0, x25
    add     x25, x25, x2
.else
    mov     x0, x24
    add     x24, x24, x2
.endif
    bl      lantern_copy
    b       6b
9:  mov     x9, #24
    add     x10, x22, x23
    stp     x9, x10, [x20, #8]
    mov     x0, #LANTERN_OK
    LEAVE 0
96: mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 0
97: mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 0
98: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
.endif
SPEC_END lc_object

/*
 * (block, scratch, out) -> status: the LightClientHeader of a BeaconBlock value (light-client.md): its
 * SSZ bytes as the message of a SignedBeaconBlock with a zero signature at the end of scratch, then
 * lantern_block_to_light_client_header. x19 block, x20 scratch, x21 out, x22 the scratch's size on
 * entry, x23 the SignedBeaconBlock ByteList, x24 the block's SSZ bytes. Locals: L the serialized size.
 */
SPEC_FUNCTION lc_anchor_header
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x20]
    ADDRESS x0, lantern_type_BeaconBlock
    mov     x1, x19
    mov     x2, x20
    add     x3, sp, #L
    CALL_GLOBAL ssz_serialize_size
    str     x22, [x20]
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    98f
    cbnz    x0, 96f
    ldr     x9, [sp, #L]                    /* the SignedBeaconBlock at the end of scratch: 104 bytes, then the serialized ByteList */
    add     x9, x9, #(104 + 7)
    and     x9, x9, #~7
    subs    x10, x22, x9
    b.lo    98f
    cmp     x10, #4096
    b.lo    98f
    add     x23, x20, x10
    str     x10, [x20]
    add     x3, x23, #104
    ldr     x9, [sp, #L]
    str     x9, [x3]
    ADDRESS x0, lantern_type_BeaconBlock
    mov     x1, x19
    mov     x2, x20
    CALL_GLOBAL ssz_serialize
    cbnz    x0, 97f
    ldr     x24, [x23, #(104 + 16)]         /* its bytes down 4, after the 100 of the fixed part */
    add     x0, x23, #124
    add     x1, x23, #128
    mov     x2, x24
    bl      lantern_copy
    add     x0, x23, #28
    mov     x1, #96
    bl      lantern_zero
    mov     w9, #100
    str     w9, [x23, #24]
    add     x9, x24, #(24 + 100)
    mov     x10, #24
    add     x11, x24, #100
    stp     x9, x10, [x23]
    str     x11, [x23, #16]
    mov     x0, x23
    mov     x1, x20
    mov     x2, x21
    bl      lantern_block_to_light_client_header
    str     x22, [x20]
    LEAVE 16
96: mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 16
97: str     x22, [x20]
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    98f
    mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 16
98: str     x22, [x20]
    mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END lc_anchor_header
