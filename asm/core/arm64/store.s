/*
 * The fork choice Store's own functions, ARM64: they read no fork's layouts.
 * Requirements: docs/reference/fork-choice.md.
 */

LEAF lantern_store_size
    ldp     x2, x3, [x0]                    /* nodes, validators */
    mov     x4, #BlockNode__mem
    umulh   x5, x2, x4
    cbnz    x5, 9f
    mul     x2, x2, x4
    lsr     x5, x3, #59                     /* validators * StoreValidator__mem fits */
    cbnz    x5, 9f
    lsl     x3, x3, #5
    adds    x2, x2, x3
    b.cs    9f
    MOVQ    x4, STORE_FIXED
    adds    x2, x2, x4
    b.cs    9f
    str     x2, [x1]
    RETURN_OK
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_store_size

/* x19 store, x20 room, x21 out, x22 node capacity, x23 validator capacity, x24 old validator count. Locals: L size. */
FUNCTION lantern_store_copy
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldp     x22, x23, [x20]
    LDQ     x9, x19, Store_blocks + 8
    cmp     x22, x9
    b.lo    9f
    LDQ     x24, x19, Store_validators + 8
    cmp     x23, x24
    b.lo    9f
    mov     x0, x20
    add     x1, sp, #L
    bl      lantern_store_size
    cbnz    x0, 9f
    ldr     x9, [sp, #L]
    ldr     x10, [x21]
    cmp     x10, x9
    b.lo    9f
    add     x0, x21, #8                     /* the fixed fields after size */
    add     x1, x19, #8
    MOVQ    x2, STORE_FIXED - 8
    bl      lantern_copy
    MOVQ    x9, STORE_FIXED                 /* the parts at their new capacities */
    str     x9, [x21, #Store_blocks]
    mov     x10, #BlockNode__mem
    madd    x11, x22, x10, x9
    str     x11, [x21, #Store_validators]
    str     x23, [x21, #(Store_validators + 8)]
    add     x0, x21, x9
    PART    x1, x2, x19, Store_blocks
    mov     x10, #BlockNode__mem
    mul     x2, x2, x10
    bl      lantern_copy
    LDQ     x9, x21, Store_validators
    add     x0, x21, x9
    PART    x1, x2, x19, Store_validators
    lsl     x2, x2, #5
    bl      lantern_copy
    LDQ     x9, x21, Store_validators       /* the new entries: no latest message, balance or flags */
    add     x9, x21, x9
    add     x9, x9, x24, lsl #5
    sub     x10, x23, x24
    mov     x11, #-1
1:  cbz     x10, 2f
    stp     xzr, x11, [x9]
    stp     xzr, xzr, [x9, #16]
    add     x9, x9, #StoreValidator__mem
    sub     x10, x10, #1
    b       1b
2:  mov     x0, #LANTERN_OK
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_store_copy

/*
 * Optimistic sync: x0 store, x1 node, x2 payload_status, x3 result. x4 node index, x6 node count,
 * x7 nodes, x8 BlockNode__mem, x9 the node.
 */
LEAF lantern_store_payload_status
    str     xzr, [x3]
    ldr     x4, [x1]
    ldr     x5, [x2]
    LDQ     x6, x0, Store_blocks + 8
    cmp     x4, x6
    b.hs    8f
    LDQ     x7, x0, Store_blocks
    add     x7, x0, x7
    mov     x8, #BlockNode__mem
    madd    x9, x4, x8, x7
    ldr     x10, [x9, #BlockNode_payload_status]
    cmp     x10, #PAYLOAD_STATUS_NOT_VALIDATED  /* only NOT_VALIDATED blocks change */
    b.ne    6f
    cmp     x5, #PAYLOAD_STATUS_VALID
    b.eq    3f
    cmp     x5, #PAYLOAD_STATUS_INVALIDATED
    b.ne    6f
    mov     x10, #PAYLOAD_STATUS_INVALIDATED    /* the block and its descendants: children come after parents */
    str     x10, [x9, #BlockNode_payload_status]
    add     x4, x4, #1
1:  cmp     x4, x6
    b.hs    6f
    madd    x9, x4, x8, x7
    ldr     x10, [x9, #BlockNode_parent]
    cmn     x10, #1
    b.eq    2f
    madd    x11, x10, x8, x7
    ldr     x11, [x11, #BlockNode_payload_status]
    cmp     x11, #PAYLOAD_STATUS_INVALIDATED
    b.ne    2f
    ldr     x11, [x9, #BlockNode_payload_status]
    cmp     x11, #PAYLOAD_STATUS_NOT_VALIDATED
    b.ne    2f
    mov     x11, #PAYLOAD_STATUS_INVALIDATED
    str     x11, [x9, #BlockNode_payload_status]
2:  add     x4, x4, #1
    b       1b
3:  mov     x10, #PAYLOAD_STATUS_VALID          /* the block and its NOT_VALIDATED ancestors */
4:  str     x10, [x9, #BlockNode_payload_status]
    ldr     x4, [x9, #BlockNode_parent]
    cmn     x4, #1
    b.eq    6f
    madd    x9, x4, x8, x7
    ldr     x11, [x9, #BlockNode_payload_status]
    cmp     x11, #PAYLOAD_STATUS_NOT_VALIDATED
    b.eq    4b
6:  RETURN_OK
8:  mov     x9, #LANTERN_INVALID_UNKNOWN_BLOCK
    str     x9, [x3]
    RETURN_OK
END_FUNCTION lantern_store_payload_status

/*
 * (store, scratch): x19 store, x20 the new index of each node (a u64 each at the end of scratch,
 * NODE_NONE when dropped), x21 the node count, x22 the finalized node, x23 the nodes, x24 i,
 * x25 the nodes kept, x26 BlockNode__mem.
 */
FUNCTION lantern_store_prune
    ENTER 0
    mov     x19, x0
    LDQ     x21, x19, Store_blocks + 8
    ldr     x9, [x1]                        /* scratch: S(1), the map at its end */
    lsl     x10, x21, #3
    add     x11, x10, #LIST_FIXED
    MOVQ    x12, LANTERN_SCRATCH_FIXED
    add     x11, x11, x12
    cmp     x9, x11
    b.lo    9f
    sub     x9, x9, x10
    add     x20, x1, x9
    LDQ     x23, x19, Store_blocks
    add     x23, x19, x23
    mov     x26, #BlockNode__mem
    add     x9, x19, #(Store_finalized_checkpoint + 8)  /* the finalized node, newest first */
    ldp     x10, x11, [x9]
    ldp     x12, x13, [x9, #16]
    mov     x22, x21
1:  cbz     x22, 8f
    sub     x22, x22, #1
    madd    x9, x22, x26, x23
    ldp     x14, x15, [x9]
    cmp     x14, x10
    ccmp    x15, x11, #0, eq
    b.ne    1b
    ldp     x14, x15, [x9, #16]
    cmp     x14, x12
    ccmp    x15, x13, #0, eq
    b.ne    1b
    mov     x24, #0                         /* the map: parents come first */
    mov     x25, #0
2:  cmp     x24, x21
    b.hs    5f
    mov     x9, #-1
    cmp     x24, x22
    b.lo    4f
    b.eq    3f
    madd    x10, x24, x26, x23
    ldr     x11, [x10, #BlockNode_parent]
    cmn     x11, #1
    b.eq    4f
    cmp     x11, x22
    b.lo    4f
    ldr     x12, [x20, x11, lsl #3]
    cmn     x12, #1
    b.eq    4f
3:  mov     x9, x25
    add     x25, x25, #1
4:  str     x9, [x20, x24, lsl #3]
    add     x24, x24, #1
    b       2b
5:  mov     x24, x22                        /* the kept nodes move down, with their new parents */
6:  cmp     x24, x21
    b.hs    7f
    ldr     x9, [x20, x24, lsl #3]
    cmn     x9, #1
    b.eq    65f
    madd    x10, x24, x26, x23
    madd    x11, x9, x26, x23
    mov     x13, #-1
    cmp     x24, x22
    b.eq    61f
    ldr     x12, [x10, #BlockNode_parent]
    ldr     x13, [x20, x12, lsl #3]
61: cmp     x10, x11
    b.eq    64f
    mov     x14, #(BlockNode__mem / 8)
    mov     x15, x10
    mov     x16, x11
62: ldr     x17, [x15], #8
    str     x17, [x16], #8
    subs    x14, x14, #1
    b.ne    62b
64: str     x13, [x11, #BlockNode_parent]
65: add     x24, x24, #1
    b       6b
7:  PART    x9, x10, x19, Store_validators  /* each latest_node to its new index */
71: cbz     x10, 73f
    ldr     x11, [x9, #StoreValidator_latest_node]
    cmp     x11, x21
    b.hs    72f
    ldr     x11, [x20, x11, lsl #3]
    str     x11, [x9, #StoreValidator_latest_node]
72: add     x9, x9, #StoreValidator__mem
    sub     x10, x10, #1
    b       71b
73: str     x25, [x19, #(Store_blocks + 8)]
    mov     x0, #LANTERN_OK
    LEAVE 0
8:  mov     x0, #LANTERN_INVALID_UNKNOWN_BLOCK
    LEAVE 0
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_store_prune
