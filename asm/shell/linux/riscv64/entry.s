/*
 * The entry point of the lantern binary for Linux on RISC-V: the arguments, without the program
 * name, as an ArgList; then lantern_app_main; then exit_group with its status.
 * Requirements: docs/reference/shell.md, Common rules. At _start, sp holds argc, then argv.
 * s1 the argument count, s2 argv, s3 the argument bytes, s4 the ArgList's size, s5 the ArgList,
 * s6 the next byte.
 */
.set ISA_RISCV64, 1
.include "ssz.inc"
.include "crypto.inc"
.include "bls12381.inc"
.include "kzg.inc"
.include "preset.inc"
.include "lantern.inc"
.include "platform.inc"

.set SYS_EXIT_GROUP, 94

    .text
    .globl _start
    .p2align 4
_start:
    .option push
    .option norelax
    lla     gp, __global_pointer$
    .option pop
    li      ra, 0
    ld      s1, 0(sp)
    addi    s2, sp, 16                      # argv[1]
    addi    s1, s1, -1
    li      s3, 0                           # the bytes of every argument
    li      t0, 0
1:  bgeu    t0, s1, 3f
    slli    t1, t0, 3
    add     t1, s2, t1
    ld      t1, 0(t1)
    li      t2, 0
2:  add     t3, t1, t2
    lbu     t3, 0(t3)
    beqz    t3, 21f
    addi    t2, t2, 1
    j       2b
21: add     s3, s3, t2
    addi    t0, t0, 1
    j       1b
3:  slli    s4, s1, 4                       # the ArgList: 40 bytes, the Arg entries, the bytes
    add     s4, s4, s3
    addi    s4, s4, 40 + 7
    andi    s4, s4, -8
    addi    sp, sp, -16
    sd      s4, 0(sp)
    mv      a0, sp
    addi    a1, sp, 8
    call    lantern_shell_map
    ld      s5, 8(sp)
    beqz    s5, 9f
    sd      s4, 0(s5)
    li      t0, 40
    sd      t0, 8(s5)
    sd      s1, 16(s5)
    slli    s6, s1, 4
    addi    s6, s6, 40
    sd      s6, 24(s5)
    sd      s3, 32(s5)
    li      t0, 0
4:  bgeu    t0, s1, 6f
    slli    t1, t0, 3
    add     t1, s2, t1
    ld      t1, 0(t1)
    slli    t4, t0, 4
    add     t4, s5, t4
    sd      s6, 40(t4)
    li      t2, 0
5:  add     t3, t1, t2
    lbu     t3, 0(t3)
    beqz    t3, 51f
    add     t5, s5, s6
    sb      t3, 0(t5)
    addi    s6, s6, 1
    addi    t2, t2, 1
    j       5b
51: sd      t2, 48(t4)
    addi    t0, t0, 1
    j       4b
6:  mv      a0, s5
    call    lantern_app_main
    j       8f
9:  li      a0, 2                           # no memory for the arguments
8:  li      a7, SYS_EXIT_GROUP
    ecall
