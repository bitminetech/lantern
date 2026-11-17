/*
 * Finding a block of Seen, RISC-V: an L0 helper of the common object and of each fork's object.
 * Requirements: docs/reference/networking.md.
 */

/* L0: a0 = the SeenBlock of root a1 in seen a0, or 0. A leaf; uses a2-a5, t0-t3. */
LOCAL_FUNCTION seen_find_block
    UNWIND_END_PROLOGUE
    PART    a2, a3, a0, Seen_blocks
1:  beqz    a3, 3f
    ld      t0, 0(a2)
    ld      t1, 0(a1)
    bne     t0, t1, 2f
    ld      t0, 8(a2)
    ld      t1, 8(a1)
    bne     t0, t1, 2f
    ld      t0, 16(a2)
    ld      t1, 16(a1)
    bne     t0, t1, 2f
    ld      t0, 24(a2)
    ld      t1, 24(a1)
    beq     t0, t1, 4f
2:  addi    a2, a2, SeenBlock__mem
    addi    a3, a3, -1
    j       1b
3:  li      a0, 0
    ret
4:  mv      a0, a2
    ret
END_FUNCTION seen_find_block
