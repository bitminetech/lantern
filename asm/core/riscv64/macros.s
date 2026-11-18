/*
 * Macros of the RISC-V core. Included once by lantern.s.
 * Register use follows the ARM64 core: s1-s10 for its x19-x28, t0-t6 and a2-a5
 * for temporaries, a6 and a7 for these macros. Trailing comments use #.
 */

/* Frame of a non-leaf function: locals at sp + 0, then ra and s1-s10. locals: a multiple of 16. */
.macro ENTER locals
    addi    sp, sp, -(\locals + 96)
    UNWIND_ALLOC (\locals + 96)
    sd      ra, (\locals + 0)(sp)
    UNWIND_SAVE ra, (\locals + 0)
    sd      s1, (\locals + 8)(sp)
    UNWIND_SAVE s1, (\locals + 8)
    sd      s2, (\locals + 16)(sp)
    UNWIND_SAVE s2, (\locals + 16)
    sd      s3, (\locals + 24)(sp)
    UNWIND_SAVE s3, (\locals + 24)
    sd      s4, (\locals + 32)(sp)
    UNWIND_SAVE s4, (\locals + 32)
    sd      s5, (\locals + 40)(sp)
    UNWIND_SAVE s5, (\locals + 40)
    sd      s6, (\locals + 48)(sp)
    UNWIND_SAVE s6, (\locals + 48)
    sd      s7, (\locals + 56)(sp)
    UNWIND_SAVE s7, (\locals + 56)
    sd      s8, (\locals + 64)(sp)
    UNWIND_SAVE s8, (\locals + 64)
    sd      s9, (\locals + 72)(sp)
    UNWIND_SAVE s9, (\locals + 72)
    sd      s10, (\locals + 80)(sp)
    UNWIND_SAVE s10, (\locals + 80)
    UNWIND_END_PROLOGUE
.endm

.macro LEAVE locals
    UNWIND_BEGIN_EPILOGUE
    ld      ra, (\locals + 0)(sp)
    UNWIND_RESTORE ra
    ld      s1, (\locals + 8)(sp)
    UNWIND_RESTORE s1
    ld      s2, (\locals + 16)(sp)
    UNWIND_RESTORE s2
    ld      s3, (\locals + 24)(sp)
    UNWIND_RESTORE s3
    ld      s4, (\locals + 32)(sp)
    UNWIND_RESTORE s4
    ld      s5, (\locals + 40)(sp)
    UNWIND_RESTORE s5
    ld      s6, (\locals + 48)(sp)
    UNWIND_RESTORE s6
    ld      s7, (\locals + 56)(sp)
    UNWIND_RESTORE s7
    ld      s8, (\locals + 64)(sp)
    UNWIND_RESTORE s8
    ld      s9, (\locals + 72)(sp)
    UNWIND_RESTORE s9
    ld      s10, (\locals + 80)(sp)
    UNWIND_RESTORE s10
    addi    sp, sp, (\locals + 96)
    UNWIND_FREE (\locals + 96)
    UNWIND_END_EPILOGUE
    ret
.endm

/* Locals of a non-leaf function start at sp. */
.set L, 0

/* Frame of a small non-leaf function: locals at sp + 0, then ra. locals: a multiple of 16. */
.macro FRAME locals
    addi    sp, sp, -(\locals + 16)
    UNWIND_ALLOC (\locals + 16)
    sd      ra, (\locals)(sp)
    UNWIND_SAVE ra, (\locals)
    UNWIND_END_PROLOGUE
.endm

.macro UNFRAME locals
    UNWIND_BEGIN_EPILOGUE
    ld      ra, (\locals)(sp)
    UNWIND_RESTORE ra
    addi    sp, sp, (\locals + 16)
    UNWIND_FREE (\locals + 16)
    UNWIND_END_EPILOGUE
    ret
.endm

/* Locals of a small frame start at sp. */
.set F, 0

/* A leaf function needs no frame. */
.macro LEAF name
    FUNCTION \name
    UNWIND_END_PROLOGUE
.endm

.macro RETURN_OK
    li      a0, LANTERN_OK
    ret
.endm

/* dst = src + imm, for any imm. Uses a7 when imm is too large for addi. */
.macro ADDQ dst, src, imm
    .if (\imm) < 2048
    addi    \dst, \src, (\imm)
    .else
    li      a7, \imm
    add     \dst, \src, a7
    .endif
.endm

/* reg = the u64 at base + off, for any off. Uses a7 when off is too large. */
.macro LDQ reg, base, off
    .if (\off) < 2048
    ld      \reg, (\off)(\base)
    .else
    li      a7, \off
    add     a7, \base, a7
    ld      \reg, 0(a7)
    .endif
.endm

/* The u64 at base + off = reg, for any off. Uses a7 when off is too large. */
.macro STQ reg, base, off
    .if (\off) < 2048
    sd      \reg, (\off)(\base)
    .else
    li      a7, \off
    add     a7, \base, a7
    sd      \reg, 0(a7)
    .endif
.endm

/* dst = 32 bytes at src. Uses a6, a7. */
.macro COPY32 dst, src
    ld      a6, 0(\src)
    ld      a7, 8(\src)
    sd      a6, 0(\dst)
    sd      a7, 8(\dst)
    ld      a6, 16(\src)
    ld      a7, 24(\src)
    sd      a6, 16(\dst)
    sd      a7, 24(\dst)
.endm

/* reg = the u64 at base + off, a 4-aligned address, read as two words. Uses tmp. */
.macro LDU64 reg, base, off, tmp
    lwu     \reg, (\off)(\base)
    lwu     \tmp, ((\off) + 4)(\base)
    slli    \tmp, \tmp, 32
    or      \reg, \reg, \tmp
.endm

/* A part of a value: base = value + its PartRef's offset, count = the PartRef's count. Uses a7. */
.macro PART base, count, value, ref
    LDQ     \count, \value, (\ref) + 8
    LDQ     \base, \value, (\ref)
    add     \base, \value, \base
.endm

/* Branch to fail when scratch s has fewer than S(k) + extra bytes for the validators of state st. Uses t0, t1, a7. */
.macro NEED_SCRATCH_B s, st, k, extra, fail
    LDQ     t0, \st, BeaconState_validators + 8
    slli    t0, t0, 3
    addi    t0, t0, LIST_FIXED
    li      t1, \k
    mul     t0, t0, t1
    li      t1, LANTERN_SCRATCH_FIXED + (\extra)
    add     t0, t0, t1
    ld      t1, 0(\s)
    bltu    t1, t0, \fail
.endm

.macro NEED_SCRATCH s, st, k, fail
    NEED_SCRATCH_B \s, \st, \k, 0, \fail
.endm

/* dst = list i of scratch s, whose size is tot: s + tot - (i + 1) * L(n), with its size set. Uses a6, a7. */
.macro SCRATCH_LIST dst, s, tot, i, nreg
    slli    a6, \nreg, 3
    addi    a6, a6, LIST_FIXED
    li      a7, (\i + 1)
    mul     a7, a6, a7
    sub     \dst, \tot, a7
    add     \dst, \s, \dst
    sd      a6, 0(\dst)
.endm

/* dst = list number ireg (a register) of scratch s, whose size is tot, with its size set. Uses a6, a7. */
.macro SCRATCH_LIST_R dst, s, tot, ireg, nreg
    slli    a6, \nreg, 3
    addi    a6, a6, LIST_FIXED
    addi    a7, \ireg, 1
    mul     a7, a6, a7
    sub     \dst, \tot, a7
    add     \dst, \s, \dst
    sd      a6, 0(\dst)
.endm

/* Give a callee scratch s without its last k lists: its size becomes tot - k * L(n). Uses a6, a7. */
.macro SCRATCH_GIVE s, tot, k, nreg
    slli    a6, \nreg, 3
    addi    a6, a6, LIST_FIXED
    li      a7, \k
    mul     a6, a6, a7
    sub     a6, \tot, a6
    sd      a6, 0(\s)
.endm

/*
 * Walk the ascending list at cursor cur (end end) to the first entry >= v;
 * set flag to 1 when it equals v, else 0. Uses a6.
 */
.macro IN_SORTED v, cur, end, flag
95: li      \flag, 0
    bgeu    \cur, \end, 98f
    ld      a6, 0(\cur)
    bgeu    a6, \v, 97f
    addi    \cur, \cur, 8
    j       95b
97: bne     a6, \v, 98f
    li      \flag, 1
98:
.endm

/*
 * After a call to a function that changes no state, with its status in a0:
 * go on when 0; return a0 through fail when it is LANTERN_BUFFER_TOO_SMALL;
 * else write it to the result at register res and branch to done. Uses a7.
 */
.macro CHECK_STATUS res, fail, done
    beqz    a0, 99f
    li      a7, LANTERN_BUFFER_TOO_SMALL
    beq     a0, a7, \fail
    sd      a0, 0(\res)
    j       \done
99:
.endm

/* Branch to label when the 32 bytes at a and at b differ. Uses a6, a7. */
.macro NE32 a, b, label
    ld      a6, 0(\a)
    ld      a7, 0(\b)
    bne     a6, a7, \label
    ld      a6, 8(\a)
    ld      a7, 8(\b)
    bne     a6, a7, \label
    ld      a6, 16(\a)
    ld      a7, 16(\b)
    bne     a6, a7, \label
    ld      a6, 24(\a)
    ld      a7, 24(\b)
    bne     a6, a7, \label
.endm

/* Branch to label when 4 bytes at a + off and at b + off differ. Uses a6, a7. */
.macro NE4 a, b, off, label
    lw      a6, (\off)(\a)
    lw      a7, (\off)(\b)
    bne     a6, a7, \label
.endm

/* Branch to label when the 32 bytes at a and at b differ; both are 4-aligned. Uses a6, a7. */
.macro NE32W a, b, label
    NE4     \a, \b, 0, \label
    NE4     \a, \b, 4, \label
    NE4     \a, \b, 8, \label
    NE4     \a, \b, 12, \label
    NE4     \a, \b, 16, \label
    NE4     \a, \b, 20, \label
    NE4     \a, \b, 24, \label
    NE4     \a, \b, 28, \label
.endm

/* Branch to label when the 48 bytes at a and at b differ; both are 4-aligned. Uses a6, a7. */
.macro NE48W a, b, label
    NE32W   \a, \b, \label
    NE4     \a, \b, 32, \label
    NE4     \a, \b, 36, \label
    NE4     \a, \b, 40, \label
    NE4     \a, \b, 44, \label
.endm

/* reg = the address of label, in this object or another. */
.macro ADDRESS reg, label
    lla     \reg, \label
.endm

/* Call lantern_<fork>_<name> for the fork in t6 (FORK_PHASE0 to FORK_FULU). Uses t5. */
.macro FORK_CALL name
    li      t5, FORK_ALTAIR
    bgeu    t6, t5, 81f
    CALL_GLOBAL lantern_phase0_\name
    j       89f
81: li      t5, FORK_BELLATRIX
    bgeu    t6, t5, 82f
    CALL_GLOBAL lantern_altair_\name
    j       89f
82: li      t5, FORK_CAPELLA
    bgeu    t6, t5, 83f
    CALL_GLOBAL lantern_bellatrix_\name
    j       89f
83: li      t5, FORK_DENEB
    bgeu    t6, t5, 84f
    CALL_GLOBAL lantern_capella_\name
    j       89f
84: li      t5, FORK_ELECTRA
    bgeu    t6, t5, 85f
    CALL_GLOBAL lantern_deneb_\name
    j       89f
85: li      t5, FORK_FULU
    bgeu    t6, t5, 86f
    CALL_GLOBAL lantern_electra_\name
    j       89f
86: CALL_GLOBAL lantern_fulu_\name
89:
.endm

/* dst = 32 bytes at src, a 4-aligned address. Uses a6, a7. */
.macro COPY32W dst, src
    lw      a6, 0(\src)
    lw      a7, 4(\src)
    sw      a6, 0(\dst)
    sw      a7, 4(\dst)
    lw      a6, 8(\src)
    lw      a7, 12(\src)
    sw      a6, 8(\dst)
    sw      a7, 12(\dst)
    lw      a6, 16(\src)
    lw      a7, 20(\src)
    sw      a6, 16(\dst)
    sw      a7, 20(\dst)
    lw      a6, 24(\src)
    lw      a7, 28(\src)
    sw      a6, 24(\dst)
    sw      a7, 28(\dst)
.endm

/* Call lantern_<fork>_<name> for the fork in t6, bellatrix to fulu. */
.macro FORK_CALL_BELLATRIX name
    li      t5, FORK_CAPELLA
    bgeu    t6, t5, 91f
    CALL_GLOBAL lantern_bellatrix_\name
    j       96f
91: li      t5, FORK_DENEB
    bgeu    t6, t5, 92f
    CALL_GLOBAL lantern_capella_\name
    j       96f
92: li      t5, FORK_ELECTRA
    bgeu    t6, t5, 93f
    CALL_GLOBAL lantern_deneb_\name
    j       96f
93: li      t5, FORK_FULU
    bgeu    t6, t5, 94f
    CALL_GLOBAL lantern_electra_\name
    j       96f
94: CALL_GLOBAL lantern_fulu_\name
96:
.endm
