/*
 * Finding a block of Seen, RISC-V: a helper of the common object and of each fork's object.
 * Requirements: docs/reference/networking.md.
 */

/* a0 = the SeenBlock of root a1 in seen a0, or 0. A leaf; uses a2-a5, t0-t3. */
LOCAL_FUNCTION lantern_seen_find_block
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
END_FUNCTION lantern_seen_find_block

/*
 * dst = the index hash of a SeenKey (networking.md, Seen): h = kind, then h = h * M + c, h * M + b,
 * h * M + a, then h xor (h >> 29). m holds SEEN_HASH_M; t a register.
 */
.macro SEEN_HASH dst, kind, a, b, c, m, t
    mul     \dst, \kind, \m
    add     \dst, \dst, \c
    mul     \dst, \dst, \m
    add     \dst, \dst, \b
    mul     \dst, \dst, \m
    add     \dst, \dst, \a
    srli    \t, \dst, 29
    xor     \dst, \dst, \t
.endm

/*
 * a0 = 1 when seen a0 holds the SeenKey (a1 kind, a2 a, a3 b, a4 c), else 0. Uses a5, t0, t1. a5 a slot,
 * t1 the mask, t2 the slots, t3 the keys less 32. Locals: sp+0 t2, t3, t4.
 */
LOCAL_FUNCTION lantern_seen_find_key
    FRAME 32
    sd      t2, 0(sp)
    sd      t3, 8(sp)
    sd      t4, 16(sp)
    li      t0, SEEN_HASH_M
    SEEN_HASH a5, a1, a2, a3, a4, t0, t1
    ld      t1, (Seen_index + 8)(a0)        # the mask of the slots
    addi    t1, t1, -1
    ld      t2, Seen_index(a0)
    add     t2, a0, t2
    ld      t3, Seen_keys(a0)
    add     t3, a0, t3
    addi    t3, t3, -SeenKey__mem
1:  and     a5, a5, t1
    slli    t4, a5, 2                       # an empty slot: not held
    add     t4, t2, t4
    lwu     t4, 0(t4)
    beqz    t4, 3f
    slli    t4, t4, 5                       # the key of position + 1
    add     t4, t3, t4
    ld      t0, 0(t4)
    bne     t0, a1, 2f
    ld      t0, 8(t4)
    bne     t0, a2, 2f
    ld      t0, 16(t4)
    bne     t0, a3, 2f
    ld      t0, 24(t4)
    beq     t0, a4, 4f
2:  addi    a5, a5, 1
    j       1b
3:  li      a0, 0
    j       5f
4:  li      a0, 1
5:  ld      t2, 0(sp)
    ld      t3, 8(sp)
    ld      t4, 16(sp)
    UNFRAME 32
END_FUNCTION lantern_seen_find_key

/*
 * Append the SeenKey (a1 kind, a2 a, a3 b, a4 c) to seen a0, which has room, and its position + 1 to the
 * first empty slot from its hash. Uses a5, t0. Locals: sp+0 t1, t2, t3.
 */
LOCAL_FUNCTION lantern_seen_add_key
    FRAME 32
    sd      t1, 0(sp)
    sd      t2, 8(sp)
    sd      t3, 16(sp)
    PART    a5, t0, a0, Seen_keys
    slli    t1, t0, 5
    add     a5, a5, t1
    sd      a1, 0(a5)
    sd      a2, 8(a5)
    sd      a3, 16(a5)
    sd      a4, 24(a5)
    addi    t3, t0, 1
    sd      t3, (Seen_keys + 8)(a0)
    li      t0, SEEN_HASH_M
    SEEN_HASH a5, a1, a2, a3, a4, t0, t1
    ld      t1, (Seen_index + 8)(a0)
    addi    t1, t1, -1
    ld      t2, Seen_index(a0)
    add     t2, a0, t2
1:  and     a5, a5, t1
    slli    t0, a5, 2
    add     t0, t2, t0
    lwu     t0, 0(t0)
    beqz    t0, 2f
    addi    a5, a5, 1
    j       1b
2:  slli    t0, a5, 2
    add     t0, t2, t0
    sw      t3, 0(t0)
    ld      t1, 0(sp)
    ld      t2, 8(sp)
    ld      t3, 16(sp)
    UNFRAME 32
END_FUNCTION lantern_seen_add_key

/*
 * The index of seen a0 from its keys: every slot empty, then each key's position + 1, in key order, at the
 * first empty slot from its hash; a0 = 0. A leaf; uses a1-a7, t0, t1. a1 the mask, a2 the slots, a3 the key,
 * a4 the keys, a5 its position + 1, a6 a slot, a7 M.
 */
LOCAL_FUNCTION lantern_seen_index
    UNWIND_END_PROLOGUE
    ld      a1, (Seen_index + 8)(a0)
    ld      a2, Seen_index(a0)
    add     a2, a0, a2
    li      a3, 0
1:  bgeu    a3, a1, 2f
    slli    t0, a3, 2
    add     t0, a2, t0
    sw      zero, 0(t0)
    addi    a3, a3, 1
    j       1b
2:  addi    a1, a1, -1
    PART    a3, a4, a0, Seen_keys
    li      a7, SEEN_HASH_M
    li      a5, 0
3:  bgeu    a5, a4, 9f
    addi    a5, a5, 1
    ld      a6, 0(a3)
    ld      t0, 24(a3)
    mul     a6, a6, a7
    add     a6, a6, t0
    ld      t0, 16(a3)
    mul     a6, a6, a7
    add     a6, a6, t0
    ld      t0, 8(a3)
    mul     a6, a6, a7
    add     a6, a6, t0
    srli    t0, a6, 29
    xor     a6, a6, t0
4:  and     a6, a6, a1
    slli    t0, a6, 2
    add     t0, a2, t0
    lwu     t1, 0(t0)
    beqz    t1, 5f
    addi    a6, a6, 1
    j       4b
5:  sw      a5, 0(t0)
    addi    a3, a3, SeenKey__mem
    j       3b
9:  li      a0, 0
    ret
END_FUNCTION lantern_seen_index
