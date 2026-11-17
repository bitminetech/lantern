/*
 * ABI check for the test runner, RISC-V (RISC-V ELF psABI, LP64D). Test code: it is not part of the library.
 *
 * abi_call(ctx) calls ctx.fn with the 11 arguments in ctx, after it sets every
 * register the callee must keep to a known value and paints ctx.paint bytes
 * of stack below the call. It then records in ctx the status, a mask of the
 * kept state that changed, and the bytes of stack the call used.
 * The layout of ctx and the bits of the mask are in tests/runner/README.md.
 *
 * It makes no unwind entries for its own frame: it runs only inside the runner.
 */

.set ISA_RISCV64, 1
.include "platform.inc"

FUNCTION abi_call
    UNWIND_END_PROLOGUE
    # Save the caller's ra, s0-s11 and fs0-fs11, and ctx at sp + 200.
    addi    sp, sp, -208
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    sd      s1, 16(sp)
    sd      s2, 24(sp)
    sd      s3, 32(sp)
    sd      s4, 40(sp)
    sd      s5, 48(sp)
    sd      s6, 56(sp)
    sd      s7, 64(sp)
    sd      s8, 72(sp)
    sd      s9, 80(sp)
    sd      s10, 88(sp)
    sd      s11, 96(sp)
    fsd     fs0, 104(sp)
    fsd     fs1, 112(sp)
    fsd     fs2, 120(sp)
    fsd     fs3, 128(sp)
    fsd     fs4, 136(sp)
    fsd     fs5, 144(sp)
    fsd     fs6, 152(sp)
    fsd     fs7, 160(sp)
    fsd     fs8, 168(sp)
    fsd     fs9, 176(sp)
    fsd     fs10, 184(sp)
    fsd     fs11, 192(sp)
    sd      a0, 200(sp)
    # Paint the stack below, from the top down, so each page is touched in order.
    ld      t1, 48(a0)
    mv      t2, sp
    li      t3, 0x5a5a5a5a5a5a5a5a
1:  addi    t2, t2, -8
    sd      t3, 0(t2)
    addi    t1, t1, -8
    bnez    t1, 1b
    sd      sp, 80(a0)
    sd      gp, 88(a0)
    sd      tp, 96(a0)
    # s11 keeps ctx; the other kept registers get known values.
    mv      s11, a0
    li      s0, 0xf1e2d3c4b5a6978
    li      s1, 0x101f2e3d4c5b6a79
    li      s2, 0x11202f3e4d5c6b7a
    li      s3, 0x1221303f4e5d6c7b
    li      s4, 0x132231404f5e6d7c
    li      s5, 0x14233241505f6e7d
    li      s6, 0x1524334251606f7e
    li      s7, 0x162534435261707f
    li      s8, 0x1726354453627180
    li      s9, 0x1827364554637281
    li      s10, 0x1928374655647382
    li      t1, 0x1f2e3d4c5b6a7988
    fmv.d.x fs0, t1
    li      t1, 0x202f3e4d5c6b7a89
    fmv.d.x fs1, t1
    li      t1, 0x21303f4e5d6c7b8a
    fmv.d.x fs2, t1
    li      t1, 0x2231404f5e6d7c8b
    fmv.d.x fs3, t1
    li      t1, 0x233241505f6e7d8c
    fmv.d.x fs4, t1
    li      t1, 0x24334251606f7e8d
    fmv.d.x fs5, t1
    li      t1, 0x2534435261707f8e
    fmv.d.x fs6, t1
    li      t1, 0x263544536271808f
    fmv.d.x fs7, t1
    li      t1, 0x2736455463728190
    fmv.d.x fs8, t1
    li      t1, 0x2837465564738291
    fmv.d.x fs9, t1
    li      t1, 0x2938475665748392
    fmv.d.x fs10, t1
    li      t1, 0x2a39485766758493
    fmv.d.x fs11, t1
    ld      t0, 0(s11)
    ld      a1, 16(s11)
    ld      a2, 24(s11)
    ld      a3, 32(s11)
    ld      a4, 40(s11)
    ld      a5, 112(s11)
    ld      a6, 120(s11)                    # arguments 7 and 8 in a6, a7; 9 to 11 on the stack
    ld      a7, 128(s11)
    addi    sp, sp, -32
    ld      t1, 136(s11)
    sd      t1, 0(sp)
    ld      t1, 144(s11)
    sd      t1, 8(sp)
    ld      t1, 152(s11)
    sd      t1, 16(sp)
    ld      a0, 8(s11)
    jalr    t0
    addi    sp, sp, 32
    li      t5, 0
    li      t1, 0xf1e2d3c4b5a6978
    xor     t1, t1, s0
    snez    t1, t1
    slli    t1, t1, 0
    or      t5, t5, t1
    li      t1, 0x101f2e3d4c5b6a79
    xor     t1, t1, s1
    snez    t1, t1
    slli    t1, t1, 1
    or      t5, t5, t1
    li      t1, 0x11202f3e4d5c6b7a
    xor     t1, t1, s2
    snez    t1, t1
    slli    t1, t1, 2
    or      t5, t5, t1
    li      t1, 0x1221303f4e5d6c7b
    xor     t1, t1, s3
    snez    t1, t1
    slli    t1, t1, 3
    or      t5, t5, t1
    li      t1, 0x132231404f5e6d7c
    xor     t1, t1, s4
    snez    t1, t1
    slli    t1, t1, 4
    or      t5, t5, t1
    li      t1, 0x14233241505f6e7d
    xor     t1, t1, s5
    snez    t1, t1
    slli    t1, t1, 5
    or      t5, t5, t1
    li      t1, 0x1524334251606f7e
    xor     t1, t1, s6
    snez    t1, t1
    slli    t1, t1, 6
    or      t5, t5, t1
    li      t1, 0x162534435261707f
    xor     t1, t1, s7
    snez    t1, t1
    slli    t1, t1, 7
    or      t5, t5, t1
    li      t1, 0x1726354453627180
    xor     t1, t1, s8
    snez    t1, t1
    slli    t1, t1, 8
    or      t5, t5, t1
    li      t1, 0x1827364554637281
    xor     t1, t1, s9
    snez    t1, t1
    slli    t1, t1, 9
    or      t5, t5, t1
    li      t1, 0x1928374655647382
    xor     t1, t1, s10
    snez    t1, t1
    slli    t1, t1, 10
    or      t5, t5, t1
    # Check sp, put it back, then check s11 against the copy of ctx on the stack.
    mv      t6, s11
    ld      t1, 80(t6)
    xor     t1, t1, sp
    snez    t1, t1
    slli    t1, t1, 63
    or      t5, t5, t1
    ld      sp, 80(t6)
    ld      t1, 200(sp)
    xor     t1, t1, s11
    snez    t1, t1
    slli    t1, t1, 11
    or      t5, t5, t1
    li      t1, 0x1f2e3d4c5b6a7988
    fmv.x.d t2, fs0
    xor     t1, t1, t2
    snez    t1, t1
    slli    t1, t1, 12
    or      t5, t5, t1
    li      t1, 0x202f3e4d5c6b7a89
    fmv.x.d t2, fs1
    xor     t1, t1, t2
    snez    t1, t1
    slli    t1, t1, 13
    or      t5, t5, t1
    li      t1, 0x21303f4e5d6c7b8a
    fmv.x.d t2, fs2
    xor     t1, t1, t2
    snez    t1, t1
    slli    t1, t1, 14
    or      t5, t5, t1
    li      t1, 0x2231404f5e6d7c8b
    fmv.x.d t2, fs3
    xor     t1, t1, t2
    snez    t1, t1
    slli    t1, t1, 15
    or      t5, t5, t1
    li      t1, 0x233241505f6e7d8c
    fmv.x.d t2, fs4
    xor     t1, t1, t2
    snez    t1, t1
    slli    t1, t1, 16
    or      t5, t5, t1
    li      t1, 0x24334251606f7e8d
    fmv.x.d t2, fs5
    xor     t1, t1, t2
    snez    t1, t1
    slli    t1, t1, 17
    or      t5, t5, t1
    li      t1, 0x2534435261707f8e
    fmv.x.d t2, fs6
    xor     t1, t1, t2
    snez    t1, t1
    slli    t1, t1, 18
    or      t5, t5, t1
    li      t1, 0x263544536271808f
    fmv.x.d t2, fs7
    xor     t1, t1, t2
    snez    t1, t1
    slli    t1, t1, 19
    or      t5, t5, t1
    li      t1, 0x2736455463728190
    fmv.x.d t2, fs8
    xor     t1, t1, t2
    snez    t1, t1
    slli    t1, t1, 20
    or      t5, t5, t1
    li      t1, 0x2837465564738291
    fmv.x.d t2, fs9
    xor     t1, t1, t2
    snez    t1, t1
    slli    t1, t1, 21
    or      t5, t5, t1
    li      t1, 0x2938475665748392
    fmv.x.d t2, fs10
    xor     t1, t1, t2
    snez    t1, t1
    slli    t1, t1, 22
    or      t5, t5, t1
    li      t1, 0x2a39485766758493
    fmv.x.d t2, fs11
    xor     t1, t1, t2
    snez    t1, t1
    slli    t1, t1, 23
    or      t5, t5, t1
    ld      t1, 88(t6)
    xor     t1, t1, gp
    snez    t1, t1
    slli    t1, t1, 24
    or      t5, t5, t1
    ld      t1, 96(t6)
    xor     t1, t1, tp
    snez    t1, t1
    slli    t1, t1, 25
    or      t5, t5, t1
    sd      a0, 56(t6)
    # The lowest painted word that changed gives the stack the call used.
    ld      t1, 48(t6)
    sub     t1, sp, t1
    li      t3, 0x5a5a5a5a5a5a5a5a
2:  bgeu    t1, sp, 3f
    ld      t2, 0(t1)
    bne     t2, t3, 3f
    addi    t1, t1, 8
    j       2b
3:  sub     t1, sp, t1
    sd      t1, 72(t6)
    sd      t5, 64(t6)
    ld      ra, 0(sp)
    ld      s0, 8(sp)
    ld      s1, 16(sp)
    ld      s2, 24(sp)
    ld      s3, 32(sp)
    ld      s4, 40(sp)
    ld      s5, 48(sp)
    ld      s6, 56(sp)
    ld      s7, 64(sp)
    ld      s8, 72(sp)
    ld      s9, 80(sp)
    ld      s10, 88(sp)
    ld      s11, 96(sp)
    fld     fs0, 104(sp)
    fld     fs1, 112(sp)
    fld     fs2, 120(sp)
    fld     fs3, 128(sp)
    fld     fs4, 136(sp)
    fld     fs5, 144(sp)
    fld     fs6, 152(sp)
    fld     fs7, 160(sp)
    fld     fs8, 168(sp)
    fld     fs9, 176(sp)
    fld     fs10, 184(sp)
    fld     fs11, 192(sp)
    addi    sp, sp, 208
    ret
END_FUNCTION abi_call
