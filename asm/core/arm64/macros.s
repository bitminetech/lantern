/*
 * Macros of the ARM64 core. Included once by lantern.s.
 */

/* Frame of a non-leaf function: x29, x30, x19-x28, then locals at sp + 96. locals: a multiple of 16. */
.macro ENTER locals
    stp     x29, x30, [sp, #-(96 + \locals)]!
    UNWIND_SAVE_FPLR_X (96 + \locals)
    mov     x29, sp
    UNWIND_SET_FP
    stp     x19, x20, [sp, #16]
    UNWIND_SAVE_REGP x19, x20, 16, (96 + \locals)
    stp     x21, x22, [sp, #32]
    UNWIND_SAVE_REGP x21, x22, 32, (96 + \locals)
    stp     x23, x24, [sp, #48]
    UNWIND_SAVE_REGP x23, x24, 48, (96 + \locals)
    stp     x25, x26, [sp, #64]
    UNWIND_SAVE_REGP x25, x26, 64, (96 + \locals)
    stp     x27, x28, [sp, #80]
    UNWIND_SAVE_REGP x27, x28, 80, (96 + \locals)
    UNWIND_END_PROLOGUE
.endm

.macro LEAVE locals
    UNWIND_BEGIN_EPILOGUE
    ldp     x27, x28, [sp, #80]
    UNWIND_RESTORE_REGP x27, x28, 80
    ldp     x25, x26, [sp, #64]
    UNWIND_RESTORE_REGP x25, x26, 64
    ldp     x23, x24, [sp, #48]
    UNWIND_RESTORE_REGP x23, x24, 48
    ldp     x21, x22, [sp, #32]
    UNWIND_RESTORE_REGP x21, x22, 32
    ldp     x19, x20, [sp, #16]
    UNWIND_RESTORE_REGP x19, x20, 16
    ldp     x29, x30, [sp], #(96 + \locals)
    UNWIND_RESTORE_FPLR_X (96 + \locals)
    UNWIND_END_EPILOGUE
    ret
.endm

/* Local of a non-leaf function: the address of byte off of the locals. */
.set L, 96

/*
 * Frame of a non-leaf function that calls functions with arguments on the stack: the frame of
 * ENTER, then out bytes below it for those arguments, from sp. Its locals are at sp + LO.
 * out: a multiple of 16.
 */
.macro ENTER_OUT locals, out
    stp     x29, x30, [sp, #-(96 + \locals)]!
    UNWIND_SAVE_FPLR_X (96 + \locals)
    mov     x29, sp
    UNWIND_SET_FP
    stp     x19, x20, [sp, #16]
    UNWIND_SAVE_REGP x19, x20, 16, (96 + \locals)
    stp     x21, x22, [sp, #32]
    UNWIND_SAVE_REGP x21, x22, 32, (96 + \locals)
    stp     x23, x24, [sp, #48]
    UNWIND_SAVE_REGP x23, x24, 48, (96 + \locals)
    stp     x25, x26, [sp, #64]
    UNWIND_SAVE_REGP x25, x26, 64, (96 + \locals)
    stp     x27, x28, [sp, #80]
    UNWIND_SAVE_REGP x27, x28, 80, (96 + \locals)
    sub     sp, sp, #(\out)
    UNWIND_ALLOC (\out)
    UNWIND_END_PROLOGUE
.endm

.macro LEAVE_OUT locals, out
    UNWIND_BEGIN_EPILOGUE
    add     sp, sp, #(\out)
    UNWIND_FREE (\out)
    ldp     x27, x28, [sp, #80]
    UNWIND_RESTORE_REGP x27, x28, 80
    ldp     x25, x26, [sp, #64]
    UNWIND_RESTORE_REGP x25, x26, 64
    ldp     x23, x24, [sp, #48]
    UNWIND_RESTORE_REGP x23, x24, 48
    ldp     x21, x22, [sp, #32]
    UNWIND_RESTORE_REGP x21, x22, 32
    ldp     x19, x20, [sp, #16]
    UNWIND_RESTORE_REGP x19, x20, 16
    ldp     x29, x30, [sp], #(96 + \locals)
    UNWIND_RESTORE_FPLR_X (96 + \locals)
    UNWIND_END_EPILOGUE
    ret
.endm

/* reg = imm, any 64-bit constant. */
.macro MOVQ reg, imm
    movz    \reg, #((\imm) & 0xffff)
    .if ((\imm) >> 16) & 0xffff
    movk    \reg, #(((\imm) >> 16) & 0xffff), lsl #16
    .endif
    .if ((\imm) >> 32) & 0xffff
    movk    \reg, #(((\imm) >> 32) & 0xffff), lsl #32
    .endif
    .if ((\imm) >> 48) & 0xffff
    movk    \reg, #(((\imm) >> 48) & 0xffff), lsl #48
    .endif
.endm

/* dst = src + imm, for any imm of 0 to 2^32 - 1. Uses x16 when imm is 4096 or more. */
.macro ADDQ dst, src, imm
    .if (\imm) < 4096
    add     \dst, \src, #(\imm)
    .else
    MOVQ    x16, \imm
    add     \dst, \src, x16
    .endif
.endm

/* reg = the u64 at base + off, for any off. Uses x16 when off is too large to encode. */
.macro LDQ reg, base, off
    .if ((\off) < 32768) && (((\off) & 7) == 0)
    ldr     \reg, [\base, #(\off)]
    .else
    MOVQ    x16, \off
    ldr     \reg, [\base, x16]
    .endif
.endm

/* The u64 at base + off = reg, for any off. Uses x16 when off is too large to encode. */
.macro STQ reg, base, off
    .if ((\off) < 32768) && (((\off) & 7) == 0)
    str     \reg, [\base, #(\off)]
    .else
    MOVQ    x16, \off
    str     \reg, [\base, x16]
    .endif
.endm

/* dst = 32 bytes at src. Uses x16, x17. */
.macro COPY32 dst, src
    ldp     x16, x17, [\src]
    stp     x16, x17, [\dst]
    ldp     x16, x17, [\src, #16]
    stp     x16, x17, [\dst, #16]
.endm

/*
 * A part of a value: base = value + its PartRef's offset, count = the PartRef's count.
 * ref is the offset of the PartRef in the value.
 */
.macro PART base, count, value, ref
    LDQ     \base, \value, (\ref)
    LDQ     \count, \value, (\ref) + 8
    add     \base, \value, \base
.endm

/* Scratch: give the bytes after the first used of scratch s to a callee, as a new Scratch at sub. Uses x16. */
.macro SCRATCH_REST sub, s, used
    ldr     x16, [\s]
    add     \sub, \s, \used
    sub     x16, x16, \used
    str     x16, [\sub]
.endm

/* Frame of a small non-leaf function: x29, x30, then locals at sp + 16. locals: a multiple of 16. */
.macro FRAME locals
    stp     x29, x30, [sp, #-(16 + \locals)]!
    UNWIND_SAVE_FPLR_X (16 + \locals)
    mov     x29, sp
    UNWIND_SET_FP
    UNWIND_END_PROLOGUE
.endm

.macro UNFRAME locals
    UNWIND_BEGIN_EPILOGUE
    ldp     x29, x30, [sp], #(16 + \locals)
    UNWIND_RESTORE_FPLR_X (16 + \locals)
    UNWIND_END_EPILOGUE
    ret
.endm

/* A leaf function needs no frame. */
.macro LEAF name
    FUNCTION \name
    UNWIND_END_PROLOGUE
.endm

/* Return LANTERN_OK from a leaf. */
.macro RETURN_OK
    mov     x0, #LANTERN_OK
    ret
.endm

/*
 * Scratch made of index lists. L(n) = 24 + 8 * n bytes is one IndexList of n
 * entries. A function that needs S(k) = LANTERN_SCRATCH_FIXED + k * L(n) bytes,
 * for the n validators of its state, keeps its own lists at the end of its
 * scratch and gives a callee the front part: the same buffer with a smaller
 * size field. A caller sets that size before each call that takes the scratch.
 */

/* Branch to fail when scratch s has fewer than S(k) bytes for the validators of state st. Uses x9, x10, x16. */
.macro NEED_SCRATCH s, st, k, fail
    LDQ     x9, \st, BeaconState_validators + 8
    lsl     x9, x9, #3
    add     x9, x9, #LIST_FIXED
    mov     x10, #\k
    mul     x9, x9, x10
    MOVQ    x10, LANTERN_SCRATCH_FIXED
    add     x9, x9, x10
    ldr     x10, [\s]
    cmp     x10, x9
    b.lo    \fail
.endm

/* dst = list i of scratch s, whose size is tot: s + tot - (i + 1) * L(n), with its size set. n in nreg. Uses x16, x17. */
.macro SCRATCH_LIST dst, s, tot, i, nreg
    lsl     x16, \nreg, #3
    add     x16, x16, #LIST_FIXED
    mov     x17, #(\i + 1)
    mul     x17, x16, x17
    sub     \dst, \tot, x17
    add     \dst, \s, \dst
    str     x16, [\dst]
.endm

/* dst = list number ireg (a register) of scratch s, whose size is tot, with its size set. Uses x16, x17. */
.macro SCRATCH_LIST_R dst, s, tot, ireg, nreg
    lsl     x16, \nreg, #3
    add     x16, x16, #LIST_FIXED
    add     x17, \ireg, #1
    mul     x17, x16, x17
    sub     \dst, \tot, x17
    add     \dst, \s, \dst
    str     x16, [\dst]
.endm

/* Give a callee scratch s without its last k lists: its size becomes tot - k * L(n). Uses x16, x17. */
.macro SCRATCH_GIVE s, tot, k, nreg
    lsl     x16, \nreg, #3
    add     x16, x16, #LIST_FIXED
    mov     x17, #\k
    mul     x16, x16, x17
    sub     x16, \tot, x16
    str     x16, [\s]
.endm

/* Whether entry v is in the ascending list walked by cursor cur with end end: sets Z when found. Uses x16. */
.macro IN_SORTED v, cur, end
95: cmp     \cur, \end
    b.hs    96f
    ldr     x16, [\cur]
    cmp     x16, \v
    b.hs    97f
    add     \cur, \cur, #8
    b       95b
96: cmp     \cur, xzr                       /* past the end: clear Z (cur is never 0) */
    b       98f
97: cmp     x16, \v                         /* Z when the entry equals v */
98:
.endm

/*
 * After a call to a function that changes no state, with its status in x0:
 * go on when 0; return x0 through fail when it is LANTERN_BUFFER_TOO_SMALL;
 * else write it to the result at register res and branch to done.
 */
.macro CHECK_STATUS res, fail, done
    cbz     x0, 99f
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    \fail
    str     x0, [\res]
    b       \done
99:
.endm

/* Branch to fail when scratch s has fewer than S(k) + extra bytes for the validators of state st. Uses x9, x10, x16. */
.macro NEED_SCRATCH_B s, st, k, extra, fail
    LDQ     x9, \st, BeaconState_validators + 8
    lsl     x9, x9, #3
    add     x9, x9, #LIST_FIXED
    mov     x10, #\k
    mul     x9, x9, x10
    MOVQ    x10, LANTERN_SCRATCH_FIXED + (\extra)
    add     x9, x9, x10
    ldr     x10, [\s]
    cmp     x10, x9
    b.lo    \fail
.endm

/* Branch to label when the 32 bytes at a and at b differ. Uses x10-x13. */
.macro NE32 a, b, label
    ldp     x10, x11, [\a]
    ldp     x12, x13, [\b]
    cmp     x10, x12
    ccmp    x11, x13, #0, eq
    b.ne    \label
    ldp     x10, x11, [\a, #16]
    ldp     x12, x13, [\b, #16]
    cmp     x10, x12
    ccmp    x11, x13, #0, eq
    b.ne    \label
.endm
