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
