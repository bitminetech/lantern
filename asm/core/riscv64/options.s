/*
 * The command line options of the binary, RISC-V: in the common object. Requirements: docs/reference/app.md, lantern_app_options.
 */

    RODATA
.include "app_options.inc"

/* a0 = 0 and a1 = the u64 of the decimal digits a0 to a1, one or more; else a0 = 1. Uses t0-t3. */
LOCAL_FUNCTION app_decimal
    UNWIND_END_PROLOGUE
    bgeu    a0, a1, 9f
    li      t0, 0
    li      t3, 10
1:  bgeu    a0, a1, 8f
    lbu     t1, 0(a0)
    addi    a0, a0, 1
    addi    t1, t1, -0x30
    li      t2, 9
    bgtu    t1, t2, 9f
    mulhu   t2, t0, t3
    bnez    t2, 9f
    mul     t0, t0, t3
    add     t2, t0, t1
    bltu    t2, t0, 9f
    mv      t0, t2
    j       1b
8:  mv      a1, t0
    li      a0, 0
    ret
9:  li      a0, 1
    ret
END_FUNCTION app_decimal

/*
 * a0 = 0 and a1 = the IPv4 address of the bytes a0 to a1, 4 decimal numbers of 0 to 255 with
 * dots between them, its 4 bytes in order in the low bytes; else a0 = 1. Uses t0-t6.
 */
LOCAL_FUNCTION app_ipv4
    UNWIND_END_PROLOGUE
    li      t0, 0                           # the address
    li      t1, 0                           # the numbers
    li      t2, 0                           # the shift of the next one
1:  li      t3, 0                           # a number
    li      t4, 0                           # its digits
2:  bgeu    a0, a1, 3f
    lbu     t5, 0(a0)
    li      t6, 0x2e                        # .
    beq     t5, t6, 3f
    addi    t5, t5, -0x30
    li      t6, 9
    bgtu    t5, t6, 9f
    addi    t4, t4, 1
    li      t6, 3
    bgtu    t4, t6, 9f
    slli    t6, t3, 2
    add     t3, t3, t6
    slli    t3, t3, 1
    add     t3, t3, t5
    addi    a0, a0, 1
    j       2b
3:  beqz    t4, 9f
    li      t6, 255
    bgtu    t3, t6, 9f
    sll     t3, t3, t2
    or      t0, t0, t3
    addi    t2, t2, 8
    addi    t1, t1, 1
    bgeu    a0, a1, 4f
    addi    a0, a0, 1                       # past the dot, to the next number
    li      t6, 4
    bgeu    t1, t6, 9f
    j       1b
4:  li      t6, 4
    bne     t1, t6, 9f
    mv      a1, t0
    li      a0, 0
    ret
9:  li      a0, 1
    ret
END_FUNCTION app_ipv4

/*
 * (args, options, fault): docs/reference/app.md. s1 args, s2 options, s3 fault, s4 the argument
 * count, s5 the next argument, s6 the Arg entries, s7 an option record, s8 the value's start, s9
 * its length, s10 the argument that holds it. Locals: L the name's start, L+8 its length, L+16
 * the option's argument, L+24 a log level.
 */
FUNCTION lantern_app_options
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      a0, s2                          # the defaults
    li      a1, AppOptions__size
    call    lantern_zero
    li      t0, APP_DEFAULT_PORT
    sd      t0, AppOptions_port(s2)
    li      t0, APP_DEFAULT_HTTP_PORT
    sd      t0, AppOptions_http_port(s2)
    li      t0, APP_DEFAULT_TARGET_PEERS
    sd      t0, AppOptions_target_peers(s2)
    li      t0, APP_DEFAULT_LOG_LEVEL
    STQ     t0, s2, AppOptions_log_level
    li      t0, APP_DEFAULT_HTTP_ADDRESS
    STQ     t0, s2, AppOptions_http_address
    li      t0, APP_DEFAULT_HTTP_CONNECTIONS
    STQ     t0, s2, AppOptions_http_max_connections
    ld      s4, (ArgList_args + 8)(s1)
    ld      t0, ArgList_args(s1)
    add     s6, s1, t0
    li      s5, 0
1:  bgeu    s5, s4, 50f                     # the next option: --name value or --name=value
    sd      s5, (L + 16)(sp)
    mv      s10, s5
    slli    t0, s5, 4
    add     t0, s6, t0
    ld      t1, 0(t0)
    ld      t2, 8(t0)
    li      t3, 3
    bltu    t2, t3, 91f
    add     t3, s1, t1
    lbu     t4, 0(t3)
    li      t5, 0x2d
    bne     t4, t5, 91f
    lbu     t4, 1(t3)
    bne     t4, t5, 91f
    addi    t1, t1, 2
    addi    t2, t2, -2
    sd      t1, L(sp)
    add     t3, s1, t1
    li      t4, 0
2:  bgeu    t4, t2, 3f                      # the name: up to = or the end
    add     t5, t3, t4
    lbu     t5, 0(t5)
    li      t6, 0x3d                        # =
    beq     t5, t6, 3f
    addi    t4, t4, 1
    j       2b
3:  sd      t4, (L + 8)(sp)
    mv      s8, t4                          # s8: where = is, s9: the length of the name and value
    mv      s9, t2
    ADDRESS s7, app_options
6:  ADDRESS t0, app_options_end
    bgeu    s7, t0, 91f                     # not an option
    ld      a0, L(sp)
    add     a0, s1, a0
    ld      a1, (L + 8)(sp)
    addi    a2, s7, 24
    ld      a3, 0(s7)
    call    config_name_is
    bnez    a0, 4f
    addi    s7, s7, APP_OPTION_BYTES
    j       6b
4:  ld      t0, 16(s7)
    li      t1, APP_OPTION_FLAG
    bne     t0, t1, 5f
    bne     s8, s9, 90f                     # a flag: no value, 1
    addi    s5, s5, 1
    li      a1, 1
    j       23f
5:  bne     s8, s9, 51f
    addi    s10, s5, 1                      # --name value: the value is the next argument
    bgeu    s10, s4, 91f
    slli    t0, s10, 4
    add     t0, s6, t0
    ld      s8, 0(t0)
    ld      s9, 8(t0)
    addi    s5, s5, 2
    j       7f
51: sub     s9, s9, s8                      # --name=value
    addi    s9, s9, -1
    ld      t0, L(sp)
    add     s8, t0, s8
    addi    s8, s8, 1
    addi    s5, s5, 1
7:  beqz    s9, 90f                         # an empty value
    ld      t0, 16(s7)
    li      t1, APP_OPTION_ENDPOINT
    bgtu    t0, t1, 20f
    bne     t0, t1, 8f
    li      t1, 7                           # the endpoint: without http://
    bltu    s9, t1, 8f
    add     a0, s1, s8
    li      a1, 7
    ADDRESS a2, app_http
    li      a3, 7
    call    config_name_is
    beqz    a0, 8f
    addi    s8, s8, 7
    addi    s9, s9, -7
    beqz    s9, 90f
8:  ld      t0, 8(s7)                       # a text: its Arg
    add     t0, s2, t0
    sd      s8, 0(t0)
    sd      s9, 8(t0)
    j       1b
20: li      t1, APP_OPTION_LEVEL
    beq     t0, t1, 24f
    add     a0, s1, s8                      # a number, or an address
    add     a1, a0, s9
    li      t1, APP_OPTION_ADDRESS
    beq     t0, t1, 21f
    call    app_decimal
    bnez    a0, 90f
    beqz    a1, 90f
    ld      t0, 16(s7)
    li      t1, 65535
    li      t2, APP_OPTION_PORT
    beq     t0, t2, 22f
    li      t1, APP_MAX_TARGET_PEERS
    li      t2, APP_OPTION_CONNECTIONS
    bne     t0, t2, 22f
    li      t1, APP_MAX_HTTP_CONNECTIONS
22: bgtu    a1, t1, 90f
    j       23f
21: call    app_ipv4
    bnez    a0, 90f
23: ld      t0, 8(s7)
    add     t0, s2, t0
    sd      a1, 0(t0)
    j       1b
24: sd      zero, (L + 24)(sp)              # a log level: one of the names of app_levels
25: ld      t0, (L + 24)(sp)
    li      t1, 4
    bgeu    t0, t1, 90f
    add     a0, s1, s8
    mv      a1, s9
    ADDRESS a2, app_levels
    slli    t1, t0, 3
    add     a2, a2, t1
    ADDRESS a3, app_level_lengths
    add     a3, a3, t0
    lbu     a3, 0(a3)
    call    config_name_is
    bnez    a0, 26f
    ld      t0, (L + 24)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 24)(sp)
    j       25b
26: ld      a1, (L + 24)(sp)
    j       23b
50: mv      s10, s4                         # --network-dir is required
    ld      t0, (AppOptions_network_dir + 8)(s2)
    beqz    t0, 90f
    ld      t0, (AppOptions_checkpoint_state + 8)(s2)   # --checkpoint-state and --checkpoint-block go together
    ld      t1, (AppOptions_checkpoint_block + 8)(s2)
    seqz    t0, t0
    seqz    t1, t1
    bne     t0, t1, 90f
    sd      zero, 0(s3)
    li      a0, LANTERN_OK
    LEAVE 32
91: ld      s10, (L + 16)(sp)               # a fault of the option's argument
90: sd      s10, 0(s3)                      # a fault of the value's argument
    li      a0, LANTERN_INVALID_OPTION
    LEAVE 32
END_FUNCTION lantern_app_options
