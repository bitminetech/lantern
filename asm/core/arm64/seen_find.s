/*
 * Finding a block of Seen, ARM64: a helper of the common object and of each fork's object.
 * Requirements: docs/reference/networking.md.
 */

/* x0 = the SeenBlock of root x1 in seen x0, or 0. A leaf; uses x2-x9. */
LOCAL_FUNCTION lantern_seen_find_block
    UNWIND_END_PROLOGUE
    PART    x2, x3, x0, Seen_blocks
    ldp     x4, x5, [x1]
    ldp     x6, x7, [x1, #16]
1:  cbz     x3, 3f
    ldp     x8, x9, [x2, #SeenBlock_root]
    cmp     x8, x4
    ccmp    x9, x5, #0, eq
    b.ne    2f
    ldp     x8, x9, [x2, #(SeenBlock_root + 16)]
    cmp     x8, x6
    ccmp    x9, x7, #0, eq
    b.eq    4f
2:  add     x2, x2, #SeenBlock__mem
    sub     x3, x3, #1
    b       1b
3:  mov     x0, #0
    ret
4:  mov     x0, x2
    ret
END_FUNCTION lantern_seen_find_block

/* m = SEEN_HASH_M, 0xFFFFFFFF9E3779B1. */
.macro SEEN_HASH_MUL m
    movn    \m, #0x61c8, lsl #16
    movk    \m, #0x79b1
.endm

/*
 * dst = the index hash of a SeenKey (networking.md, Seen): h = kind, then h = h * M + c, h * M + b,
 * h * M + a, then h xor (h >> 29). m holds M.
 */
.macro SEEN_HASH dst, kind, a, b, c, m
    madd    \dst, \kind, \m, \c
    madd    \dst, \dst, \m, \b
    madd    \dst, \dst, \m, \a
    eor     \dst, \dst, \dst, lsr #29
.endm

/*
 * x0 = 1 when seen x0 holds the SeenKey (x1 kind, x2 a, x3 b, x4 c), else 0. Uses x5-x8. x5 a slot, x6 the
 * mask, x7 the slots, x0 the keys less 32. Locals: sp+16 x9, x10.
 */
LOCAL_FUNCTION lantern_seen_find_key
    FRAME 16
    stp     x9, x10, [sp, #16]
    SEEN_HASH_MUL x8
    SEEN_HASH x5, x1, x2, x3, x4, x8
    ldr     x6, [x0, #(Seen_index + 8)]     /* the mask of the slots */
    sub     x6, x6, #1
    ldr     x7, [x0, #Seen_index]
    add     x7, x0, x7
    ldr     x8, [x0, #Seen_keys]
    add     x0, x0, x8
    sub     x0, x0, #SeenKey__mem
1:  and     x5, x5, x6
    ldr     w8, [x7, x5, lsl #2]            /* an empty slot: not held */
    cbz     w8, 3f
    add     x8, x0, x8, lsl #5              /* the key of position + 1 */
    ldp     x9, x10, [x8]
    cmp     x9, x1
    ccmp    x10, x2, #0, eq
    b.ne    2f
    ldp     x9, x10, [x8, #16]
    cmp     x9, x3
    ccmp    x10, x4, #0, eq
    b.eq    4f
2:  add     x5, x5, #1
    b       1b
3:  mov     x0, #0
    b       5f
4:  mov     x0, #1
5:  ldp     x9, x10, [sp, #16]
    UNFRAME 16
END_FUNCTION lantern_seen_find_key

/*
 * Append the SeenKey (x1 kind, x2 a, x3 b, x4 c) to seen x0, which has room, and its position + 1 to the
 * first empty slot from its hash. Uses x5, x6. Locals: sp+16 x7, x8, x9.
 */
LOCAL_FUNCTION lantern_seen_add_key
    FRAME 32
    stp     x7, x8, [sp, #16]
    str     x9, [sp, #32]
    PART    x5, x6, x0, Seen_keys
    add     x5, x5, x6, lsl #5
    stp     x1, x2, [x5]
    stp     x3, x4, [x5, #16]
    add     x9, x6, #1
    str     x9, [x0, #(Seen_keys + 8)]
    SEEN_HASH_MUL x8
    SEEN_HASH x5, x1, x2, x3, x4, x8
    ldr     x6, [x0, #(Seen_index + 8)]
    sub     x6, x6, #1
    ldr     x7, [x0, #Seen_index]
    add     x7, x0, x7
1:  and     x5, x5, x6
    ldr     w8, [x7, x5, lsl #2]
    cbz     w8, 2f
    add     x5, x5, #1
    b       1b
2:  str     w9, [x7, x5, lsl #2]
    ldp     x7, x8, [sp, #16]
    ldr     x9, [sp, #32]
    UNFRAME 32
END_FUNCTION lantern_seen_add_key

/*
 * The index of seen x0 from its keys: every slot empty, then each key's position + 1, in key order, at the
 * first empty slot from its hash; x0 = 0. A leaf; uses x1-x9. x1 the mask, x2 the slots, x3 the key, x4 the
 * keys, x5 its position + 1, x6 a slot, x9 M.
 */
LOCAL_FUNCTION lantern_seen_index
    UNWIND_END_PROLOGUE
    ldr     x1, [x0, #(Seen_index + 8)]
    ldr     x2, [x0, #Seen_index]
    add     x2, x0, x2
    mov     x3, #0
1:  cmp     x3, x1
    b.hs    2f
    str     wzr, [x2, x3, lsl #2]
    add     x3, x3, #1
    b       1b
2:  sub     x1, x1, #1
    PART    x3, x4, x0, Seen_keys
    SEEN_HASH_MUL x9
    mov     x5, #0
3:  cmp     x5, x4
    b.hs    9f
    add     x5, x5, #1
    ldp     x6, x7, [x3]
    ldr     x8, [x3, #24]
    madd    x6, x6, x9, x8
    ldr     x8, [x3, #16]
    madd    x6, x6, x9, x8
    madd    x6, x6, x9, x7
    eor     x6, x6, x6, lsr #29
4:  and     x6, x6, x1
    ldr     w8, [x2, x6, lsl #2]
    cbz     w8, 5f
    add     x6, x6, #1
    b       4b
5:  str     w5, [x2, x6, lsl #2]
    add     x3, x3, #SeenKey__mem
    b       3b
9:  mov     x0, #0
    ret
END_FUNCTION lantern_seen_index
