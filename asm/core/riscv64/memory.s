/*
 * Copy and zero, RISC-V: L0 helpers that every object of the core includes.
 */

/* dst a0, src a1, n a2: 32 bytes at a time when both are 8-aligned, else a byte at a time. */
LOCAL_FUNCTION lantern_copy
    UNWIND_END_PROLOGUE
    or      a3, a0, a1
    andi    a3, a3, 7
    bnez    a3, 3f
    li      a3, 32
1:  bltu    a2, a3, 2f
    ld      a4, 0(a1)
    ld      a5, 8(a1)
    ld      a6, 16(a1)
    ld      a7, 24(a1)
    sd      a4, 0(a0)
    sd      a5, 8(a0)
    sd      a6, 16(a0)
    sd      a7, 24(a0)
    addi    a1, a1, 32
    addi    a0, a0, 32
    addi    a2, a2, -32
    j       1b
2:  li      a3, 8
21: bltu    a2, a3, 3f
    ld      a4, 0(a1)
    sd      a4, 0(a0)
    addi    a1, a1, 8
    addi    a0, a0, 8
    addi    a2, a2, -8
    j       21b
3:  beqz    a2, 4f
    lbu     a4, 0(a1)
    sb      a4, 0(a0)
    addi    a1, a1, 1
    addi    a0, a0, 1
    addi    a2, a2, -1
    j       3b
4:  ret
END_FUNCTION lantern_copy

LOCAL_FUNCTION lantern_zero
    UNWIND_END_PROLOGUE
    andi    a2, a0, 7
    bnez    a2, 3f
    li      a2, 8
1:  bltu    a1, a2, 3f
    sd      zero, 0(a0)
    addi    a0, a0, 8
    addi    a1, a1, -8
    j       1b
3:  beqz    a1, 4f
    sb      zero, 0(a0)
    addi    a0, a0, 1
    addi    a1, a1, -1
    j       3b
4:  ret
END_FUNCTION lantern_zero
