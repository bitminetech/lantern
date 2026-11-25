/*
 * Finding a block of Seen, ARM64: an L0 helper of the common object and of each fork's object.
 * Requirements: docs/reference/networking.md.
 */

/* L0: x0 = the SeenBlock of root x1 in seen x0, or 0. A leaf; uses x2-x9. */
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
