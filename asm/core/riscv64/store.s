/*
 * The fork choice Store's own functions, RISC-V: they read no fork's layouts.
 * Requirements: docs/reference/fork-choice.md.
 */

LEAF lantern_store_size
    ld      a2, 0(a0)                       # nodes
    ld      a3, 8(a0)                       # validators
    li      a4, BlockNode__mem
    mulhu   a5, a2, a4
    bnez    a5, 9f
    mul     a2, a2, a4
    srli    a5, a3, 59                      # validators * StoreValidator__mem fits
    bnez    a5, 9f
    slli    a3, a3, 5
    add     a3, a2, a3
    bltu    a3, a2, 9f
    li      a4, STORE_FIXED
    add     a4, a3, a4
    bltu    a4, a3, 9f
    sd      a4, 0(a1)
    RETURN_OK
9:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_store_size

/* s1 store, s2 room, s3 out, s4 node capacity, s5 validator capacity, s6 old validator count. Locals: L size. */
FUNCTION lantern_store_copy
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, 0(s2)
    ld      s5, 8(s2)
    ld      t0, (Store_blocks + 8)(s1)
    bltu    s4, t0, 9f
    ld      s6, (Store_validators + 8)(s1)
    bltu    s5, s6, 9f
    mv      a0, s2
    addi    a1, sp, L
    call    lantern_store_size
    bnez    a0, 9f
    ld      t0, L(sp)
    ld      t1, 0(s3)
    bltu    t1, t0, 9f
    addi    a0, s3, 8                       # the fixed fields after size
    addi    a1, s1, 8
    li      a2, STORE_FIXED - 8
    call    lantern_copy
    li      t0, STORE_FIXED                 # the parts at their new capacities
    sd      t0, Store_blocks(s3)
    li      t1, BlockNode__mem
    mul     t2, s4, t1
    add     t2, t2, t0
    sd      t2, Store_validators(s3)
    sd      s5, (Store_validators + 8)(s3)
    add     a0, s3, t0
    PART    a1, a2, s1, Store_blocks
    li      t1, BlockNode__mem
    mul     a2, a2, t1
    call    lantern_copy
    ld      t0, Store_validators(s3)
    add     a0, s3, t0
    PART    a1, a2, s1, Store_validators
    slli    a2, a2, 5
    call    lantern_copy
    ld      t0, Store_validators(s3)        # the new entries: no latest message, balance or flags
    add     t0, s3, t0
    slli    t1, s6, 5
    add     t0, t0, t1
    sub     t1, s5, s6
    li      t2, -1
1:  beqz    t1, 2f
    sd      zero, 0(t0)
    sd      t2, 8(t0)
    sd      zero, 16(t0)
    sd      zero, 24(t0)
    addi    t0, t0, StoreValidator__mem
    addi    t1, t1, -1
    j       1b
2:  li      a0, LANTERN_OK
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_store_copy

/*
 * Optimistic sync: a0 store, a1 node, a2 payload_status, a3 result. a4 node index, a5 payload_status,
 * t0 node count, t1 nodes, t2 BlockNode__mem, t3 the node.
 */
LEAF lantern_store_payload_status
    sd      zero, 0(a3)
    ld      a4, 0(a1)
    ld      a5, 0(a2)
    ld      t0, (Store_blocks + 8)(a0)
    bgeu    a4, t0, 8f
    ld      t1, Store_blocks(a0)
    add     t1, a0, t1
    li      t2, BlockNode__mem
    mul     t3, a4, t2
    add     t3, t1, t3
    ld      t4, BlockNode_payload_status(t3)
    li      t6, PAYLOAD_STATUS_NOT_VALIDATED    # only NOT_VALIDATED blocks change
    bne     t4, t6, 6f
    beqz    a5, 3f
    li      t5, PAYLOAD_STATUS_INVALIDATED
    bne     a5, t5, 6f
    sd      t5, BlockNode_payload_status(t3)    # the block and its descendants: children come after parents
    addi    a4, a4, 1
1:  bgeu    a4, t0, 6f
    mul     t3, a4, t2
    add     t3, t1, t3
    ld      t4, BlockNode_parent(t3)
    li      a6, -1
    beq     t4, a6, 2f
    mul     t4, t4, t2
    add     t4, t1, t4
    ld      t4, BlockNode_payload_status(t4)
    bne     t4, t5, 2f
    ld      t4, BlockNode_payload_status(t3)
    bne     t4, t6, 2f
    sd      t5, BlockNode_payload_status(t3)
2:  addi    a4, a4, 1
    j       1b
3:  sd      zero, BlockNode_payload_status(t3)  # VALID: the block and its NOT_VALIDATED ancestors
    ld      a4, BlockNode_parent(t3)
    li      a6, -1
    beq     a4, a6, 6f
    mul     t3, a4, t2
    add     t3, t1, t3
    ld      t4, BlockNode_payload_status(t3)
    beq     t4, t6, 3b
6:  li      a0, LANTERN_OK
    ret
8:  li      t0, LANTERN_INVALID_UNKNOWN_BLOCK
    sd      t0, 0(a3)
    li      a0, LANTERN_OK
    ret
END_FUNCTION lantern_store_payload_status
