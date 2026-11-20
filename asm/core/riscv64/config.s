/*
 * The network config file, RISC-V: in the common object. Requirements: docs/reference/config.md.
 */

/* A record of CONFIG_KEYS: the name's length, its CONFIG_* offset, its kind, then the name in CONFIG_KEY_NAME_MAX bytes. */
.set CONFIG_KEY_BYTES, 24 + CONFIG_KEY_NAME_MAX
.macro CONFIG_KEY_RECORD name, offset, kind
    .quad 72f - 71f, \offset, \kind
71: .ascii "\name"
72: .space CONFIG_KEY_NAME_MAX - (72b - 71b)
.endm

    RODATA
    .p2align 3
config_keys:
    CONFIG_KEYS CONFIG_KEY_RECORD
config_keys_end:
config_schedule_name:
    .ascii "BLOB_SCHEDULE"
config_epoch_name:
    .ascii "EPOCH"
config_max_name:
    .ascii "MAX_BLOBS_PER_BLOCK"

/* \out = the value of the hex digit in \in, or 16 when it is not one. Uses \tmp. */
.macro CONFIG_HEX out, in, tmp
    addi    \out, \in, -0x30
    li      \tmp, 10
    bltu    \out, \tmp, 91f
    ori     \out, \in, 0x20                 # a to f, either case
    addi    \out, \out, -0x61
    li      \tmp, 6
    bltu    \out, \tmp, 92f
    li      \out, 16
    j       91f
92: addi    \out, \out, 10
91:
.endm

/* a0 = 1 when the a1 bytes at a0 are the a3 bytes at a2, else 0. Uses t0, t1. */
LOCAL_FUNCTION config_name_is
    UNWIND_END_PROLOGUE
    bne     a1, a3, 2f
1:  beqz    a1, 3f
    lbu     t0, 0(a0)
    lbu     t1, 0(a2)
    bne     t0, t1, 2f
    addi    a0, a0, 1
    addi    a2, a2, 1
    addi    a1, a1, -1
    j       1b
2:  li      a0, 0
    ret
3:  li      a0, 1
    ret
END_FUNCTION config_name_is

/* The value bytes a0 to a1 without a pair of quotes: a0 = 0, a1 their start, a2 their end; a0 = 1 for a quote with no end. Uses t0-t2. */
LOCAL_FUNCTION config_unquote
    UNWIND_END_PROLOGUE
    mv      a2, a1
    mv      a1, a0
    bgeu    a1, a2, 8f
    lbu     t0, 0(a1)
    li      t1, 0x27                        # '
    beq     t0, t1, 1f
    li      t1, 0x22                        # "
    bne     t0, t1, 8f
1:  sub     t1, a2, a1
    li      t2, 2
    bltu    t1, t2, 9f
    lbu     t1, -1(a2)
    bne     t1, t0, 9f
    addi    a1, a1, 1
    addi    a2, a2, -1
8:  li      a0, 0
    ret
9:  li      a0, 1
    ret
END_FUNCTION config_unquote

/* a0 = 0 and a1 = the u64 of the bytes a0 to a1: decimal, or 0x and 1 to 16 hex digits; else a0 = 1. Uses t0-t4. */
LOCAL_FUNCTION config_u64
    UNWIND_END_PROLOGUE
    sub     t0, a1, a0
    beqz    t0, 9f
    li      t1, 0                           # the value
    li      t2, 3
    bltu    t0, t2, 3f
    lbu     t2, 0(a0)                       # 0x
    li      t3, 0x30
    bne     t2, t3, 3f
    lbu     t2, 1(a0)
    li      t3, 0x78
    bne     t2, t3, 3f
    addi    t0, t0, -2
    li      t2, 16
    bgtu    t0, t2, 9f
    addi    a0, a0, 2
2:  bgeu    a0, a1, 8f
    lbu     t2, 0(a0)
    addi    a0, a0, 1
    CONFIG_HEX t3, t2, t4
    li      t4, 16
    bgeu    t3, t4, 9f
    slli    t1, t1, 4
    or      t1, t1, t3
    j       2b
3:  bgeu    a0, a1, 8f                      # decimal
    lbu     t2, 0(a0)
    addi    a0, a0, 1
    addi    t2, t2, -0x30
    li      t3, 9
    bgtu    t2, t3, 9f
    li      t3, 10
    mulhu   t4, t1, t3
    bnez    t4, 9f
    mul     t1, t1, t3
    add     t4, t1, t2
    bltu    t4, t1, 9f
    mv      t1, t4
    j       3b
8:  mv      a1, t1
    li      a0, 0
    ret
9:  li      a0, 1
    ret
END_FUNCTION config_u64

/* a0 = 0 when the bytes a0 to a1 are 0x and 2 * a3 hex digits, whose a3 bytes go to a2 in order; else 1. Uses t0-t3. */
LOCAL_FUNCTION config_hex_bytes
    UNWIND_END_PROLOGUE
    sub     t0, a1, a0
    slli    t1, a3, 1
    addi    t1, t1, 2
    bne     t0, t1, 9f
    lbu     t0, 0(a0)                       # 0x
    li      t1, 0x30
    bne     t0, t1, 9f
    lbu     t0, 1(a0)
    li      t1, 0x78
    bne     t0, t1, 9f
    addi    a0, a0, 2
1:  beqz    a3, 8f
    lbu     t0, 0(a0)
    CONFIG_HEX t1, t0, t2
    li      t2, 16
    bgeu    t1, t2, 9f
    lbu     t0, 1(a0)
    CONFIG_HEX t3, t0, t2
    li      t2, 16
    bgeu    t3, t2, 9f
    slli    t1, t1, 4
    or      t1, t1, t3
    sb      t1, 0(a2)
    addi    a2, a2, 1
    addi    a0, a0, 2
    addi    a3, a3, -1
    j       1b
8:  li      a0, 0
    ret
9:  li      a0, 1
    ret
END_FUNCTION config_hex_bytes

/* a0 = 0 when the bytes a0 to a1 are the decimal digits of a number below 2^256, then little endian at a2 (32 bytes); else 1. Uses t0-t6. */
LOCAL_FUNCTION config_uint256
    UNWIND_END_PROLOGUE
    sd      zero, 0(a2)
    sd      zero, 8(a2)
    sd      zero, 16(a2)
    sd      zero, 24(a2)
    bgeu    a0, a1, 9f
1:  bgeu    a0, a1, 8f
    lbu     t0, 0(a0)                       # the carry: the digit
    addi    a0, a0, 1
    addi    t0, t0, -0x30
    li      t1, 9
    bgtu    t0, t1, 9f
    li      t1, 10
    li      t2, 0                           # each limb: limb * 10 + carry
2:  add     t3, a2, t2
    ld      t4, 0(t3)
    mul     t5, t4, t1
    mulhu   t6, t4, t1
    add     t5, t5, t0
    sltu    t0, t5, t0
    add     t0, t6, t0
    sd      t5, 0(t3)
    addi    t2, t2, 8
    li      t4, 32
    bltu    t2, t4, 2b
    bnez    t0, 9f                          # 2^256 or more
    j       1b
8:  li      a0, 0
    ret
9:  li      a0, 1
    ret
END_FUNCTION config_uint256

/*
 * a0 = 0 when the value bytes a1 to a2, without a pair of quotes, are a value of the kind a0,
 * then at a3: 8 bytes (u64; Version: 4 bytes and 4 zero bytes) or 32 (Uint256, Hash32); else 1.
 * s1 the kind, s2 out.
 */
LOCAL_FUNCTION config_value
    ENTER 0
    mv      s1, a0
    mv      s2, a3
    mv      a0, a1
    mv      a1, a2
    call    config_unquote
    bnez    a0, 9f
    mv      a0, a1
    mv      a1, a2
    li      t0, CONFIG_KIND_U64
    bne     s1, t0, 1f
    call    config_u64
    bnez    a0, 9f
    sd      a1, 0(s2)
    j       9f
1:  li      t0, CONFIG_KIND_VERSION
    bne     s1, t0, 2f
    sd      zero, 0(s2)
    mv      a2, s2
    li      a3, 4
    call    config_hex_bytes
    j       9f
2:  li      t0, CONFIG_KIND_UINT256
    bne     s1, t0, 3f
    mv      a2, s2
    call    config_uint256
    j       9f
3:  li      t0, CONFIG_KIND_HASH32
    bne     s1, t0, 4f
    mv      a2, s2                          # Hash32
    li      a3, 32
    call    config_hex_bytes
    j       9f
4:  li      t0, CONFIG_KIND_ADDRESS
    bne     s1, t0, 5f
    sd      zero, 0(s2)                     # Address: 20 bytes, then 12 zero bytes
    sd      zero, 8(s2)
    sd      zero, 16(s2)
    sd      zero, 24(s2)
    mv      a2, s2
    li      a3, 20
    call    config_hex_bytes
    j       9f
5:  mv      a2, s2                          # Text: to s2, when it is not 0
    call    config_text
9:  LEAVE 0
END_FUNCTION config_value

/*
 * a0 = 0 when the bytes a0 to a1 are a text (0 to CONFIG_TEXT_MAX bytes, each 0x20 to 0x7e but
 * " and \); then, when a2 is not 0, at a2 its count and CONFIG_TEXT_MAX bytes: its bytes, then
 * zero bytes. Else a0 = 1. Uses t0-t3.
 */
LOCAL_FUNCTION config_text
    UNWIND_END_PROLOGUE
    sub     t0, a1, a0
    li      t1, CONFIG_TEXT_MAX
    bgtu    t0, t1, 9f
    mv      t1, a0
1:  bgeu    t1, a1, 2f
    lbu     t2, 0(t1)
    addi    t1, t1, 1
    addi    t3, t2, -0x20
    sltiu   t3, t3, (0x7e - 0x20 + 1)
    beqz    t3, 9f
    li      t3, 0x22
    beq     t2, t3, 9f
    li      t3, 0x5c
    beq     t2, t3, 9f
    j       1b
2:  beqz    a2, 8f
    sd      t0, 0(a2)
    li      t1, 0
3:  li      t2, CONFIG_TEXT_MAX
    bgeu    t1, t2, 8f
    li      t2, 0
    bgeu    t1, t0, 4f
    add     t3, a0, t1
    lbu     t2, 0(t3)
4:  add     t3, a2, t1
    sb      t2, 8(t3)
    addi    t1, t1, 1
    j       3b
8:  li      a0, 0
    ret
9:  li      a0, 1
    ret
END_FUNCTION config_text

/*
 * In config_scan: close the open entry of the schedule: to 80f (a fault at its line) without
 * both fields; else with write, its EPOCH and MAX_BLOBS_PER_BLOCK as schedule entry s9 - 1. Uses t0, t1.
 */
.macro CONFIG_ENTRY_END
    andi    t0, s10, 4
    beqz    t0, 99f
    andi    t0, s10, 3
    li      t1, 3
    bne     t0, t1, 80f
    beqz    s2, 98f
    addi    t0, s9, -1
    slli    t0, t0, 4
    add     t0, t0, s1
    ld      t1, (L + 16)(sp)
    sd      t1, CONFIG_BLOB_SCHEDULE(t0)
    ld      t1, (L + 24)(sp)
    sd      t1, (CONFIG_BLOB_SCHEDULE + 8)(t0)
98: li      s10, 0
99:
.endm

.set CONFIG_MODE_NONE, 0                    # no key yet
.set CONFIG_MODE_SCALAR, 1                  # a key lantern reads, or BLOB_SCHEDULE: []
.set CONFIG_MODE_SKIP, 2                    # a key lantern does not read
.set CONFIG_MODE_SCHEDULE, 3                # the entries of BLOB_SCHEDULE

/*
 * a0 = 0, or the number of the first faulty line, of the config text a0 (a ByteList); with
 * a2 = 1, writes its values into the config a1. s1 config, s2 write, s3 the next line, s4 the
 * text end, s5 the line number, s6 the mode or a key record, s7 the line start, s8 the line end,
 * s9 the schedule's entries, s10 the open entry: bit 0 EPOCH, bit 1 MAX_BLOBS_PER_BLOCK, bit 2
 * open. Locals: L the entry's line, L+8 its dash column, L+16 its EPOCH, L+24 its
 * MAX_BLOBS_PER_BLOCK, L+32 1 when the text gives BLOB_SCHEDULE, L+40 a value (32 bytes) or a
 * field, L+72 the value's start or a column, L+80 the key's length or a position.
 */
LOCAL_FUNCTION config_scan
    ENTER 96
    mv      s1, a1
    mv      s2, a2
    ld      t0, 8(a0)
    add     s3, a0, t0
    ld      t0, 16(a0)
    add     s4, s3, t0
    li      s5, 0
    li      s6, CONFIG_MODE_NONE
    li      s9, 0
    li      s10, 0
    sd      zero, (L + 32)(sp)
10: bgeu    s3, s4, 90f                     # the next line
    addi    s5, s5, 1
    mv      s7, s3
11: bgeu    s3, s4, 12f                     # its end: an LF or the text end
    lbu     t0, 0(s3)
    li      t1, 10
    beq     t0, t1, 12f
    addi    s3, s3, 1
    j       11b
12: mv      s8, s3
    bgeu    s3, s4, 13f
    addi    s3, s3, 1                       # past the LF, and a CR before it
    bleu    s8, s7, 13f
    lbu     t0, -1(s8)
    li      t1, 13
    bne     t0, t1, 13f
    addi    s8, s8, -1
13: mv      t0, s7                          # a comment: # at the start or after a space or tab, outside quotes
    li      t1, 0                           # the open quote
14: bgeu    t0, s8, 17f
    lbu     t2, 0(t0)
    beqz    t1, 15f
    bne     t2, t1, 16f
    li      t1, 0
    j       16f
15: li      t3, 0x27
    beq     t2, t3, 151f
    li      t3, 0x22
    bne     t2, t3, 152f
151: mv     t1, t2
    j       16f
152: li     t3, 0x23                        # #
    bne     t2, t3, 16f
    beq     t0, s7, 153f
    lbu     t3, -1(t0)
    li      t4, 0x20
    beq     t3, t4, 153f
    li      t4, 9
    bne     t3, t4, 16f
153: mv     s8, t0
    j       17f
16: addi    t0, t0, 1
    j       14b
17: bleu    s8, s7, 10b                     # the spaces and tabs at the end; an empty line
    lbu     t0, -1(s8)
    li      t1, 0x20
    beq     t0, t1, 171f
    li      t1, 9
    bne     t0, t1, 18f
171: addi   s8, s8, -1
    j       17b
18: sub     t0, s8, s7                      # ---
    li      t1, 3
    bne     t0, t1, 19f
    li      t1, 0x2d
    lbu     t0, 0(s7)
    bne     t0, t1, 19f
    lbu     t0, 1(s7)
    bne     t0, t1, 19f
    lbu     t0, 2(s7)
    beq     t0, t1, 10b
19: lbu     t0, 0(s7)
    li      t1, 0x20
    beq     t0, t1, 50f
    CONFIG_ENTRY_END                        # KEY: and nothing, or spaces and a value
    mv      t0, s7
21: bgeu    t0, s8, 89f
    lbu     t1, 0(t0)
    li      t2, 0x3a                        # :
    beq     t1, t2, 23f
    addi    t2, t1, -0x30                   # 0 to 9, _, A to Z, a to z
    li      t3, 10
    bltu    t2, t3, 22f
    li      t3, 0x5f
    beq     t1, t3, 22f
    ori     t2, t1, 0x20
    addi    t2, t2, -0x61
    li      t3, 26
    bgeu    t2, t3, 89f
22: addi    t0, t0, 1
    j       21b
23: sub     t2, t0, s7
    beqz    t2, 89f
    sd      t2, (L + 80)(sp)
    addi    t0, t0, 1
    bgeu    t0, s8, 25f
    lbu     t1, 0(t0)
    li      t3, 0x20
    bne     t1, t3, 89f
24: lbu     t1, 0(t0)                       # the spaces before the value
    li      t3, 0x20
    bne     t1, t3, 25f
    addi    t0, t0, 1
    j       24b
25: sd      t0, (L + 72)(sp)
    mv      a0, s7
    ld      a1, (L + 80)(sp)
    ADDRESS a2, config_schedule_name
    li      a3, 13
    call    config_name_is
    bnez    a0, 30f
    ADDRESS s6, config_keys
26: ADDRESS t0, config_keys_end
    bgeu    s6, t0, 27f
    mv      a0, s7
    ld      a1, (L + 80)(sp)
    addi    a2, s6, 24
    ld      a3, 0(s6)
    call    config_name_is
    bnez    a0, 28f
    addi    s6, s6, CONFIG_KEY_BYTES
    j       26b
27: li      s6, CONFIG_MODE_SKIP            # a key lantern does not read
    j       10b
28: ld      a0, 16(s6)                      # a key lantern reads
    ld      a1, (L + 72)(sp)
    mv      a2, s8
    addi    a3, sp, L + 40
    li      t0, CONFIG_KIND_TEXT            # a text: straight into the config, when it writes
    bne     a0, t0, 280f
    li      a3, 0
    beqz    s2, 280f
    ld      a3, 8(s6)
    add     a3, s1, a3
280: call   config_value
    bnez    a0, 89f
    beqz    s2, 29f
    ld      t2, 16(s6)
    li      t3, CONFIG_KIND_TEXT
    beq     t2, t3, 29f
    ld      t0, 8(s6)                       # 8 bytes, or 32 for a Uint256, a Hash32 or an Address
    add     t0, s1, t0
    ld      t1, (L + 40)(sp)
    sd      t1, 0(t0)
    ld      t2, 16(s6)
    li      t3, CONFIG_KIND_VERSION
    bleu    t2, t3, 29f
    ld      t1, (L + 48)(sp)
    sd      t1, 8(t0)
    ld      t1, (L + 56)(sp)
    sd      t1, 16(t0)
    ld      t1, (L + 64)(sp)
    sd      t1, 24(t0)
29: li      s6, CONFIG_MODE_SCALAR
    j       10b
30: li      s9, 0                           # BLOB_SCHEDULE: nothing, then its entries; or []
    li      t0, 1
    sd      t0, (L + 32)(sp)
    li      s6, CONFIG_MODE_SCHEDULE
    ld      t0, (L + 72)(sp)
    bgeu    t0, s8, 10b
    sub     t1, s8, t0
    li      t2, 2
    bne     t1, t2, 89f
    lbu     t1, 0(t0)
    li      t2, 0x5b
    bne     t1, t2, 89f
    lbu     t1, 1(t0)
    li      t2, 0x5d
    bne     t1, t2, 89f
    li      s6, CONFIG_MODE_SCALAR
    j       10b
50: li      t0, CONFIG_MODE_SKIP            # an indented line
    beq     s6, t0, 10b
    li      t0, CONFIG_MODE_SCHEDULE
    bne     s6, t0, 89f
    mv      t0, s7
51: lbu     t1, 0(t0)
    li      t2, 0x20
    bne     t1, t2, 52f
    addi    t0, t0, 1
    j       51b
52: sub     t3, t0, s7                      # its column
    li      t2, 0x2d
    bne     t1, t2, 55f
    addi    t4, t0, 1                       # - and a space: a new entry
    bgeu    t4, s8, 89f
    lbu     t1, 0(t4)
    li      t2, 0x20
    bne     t1, t2, 89f
    sd      t3, (L + 72)(sp)
    sd      t4, (L + 80)(sp)
    CONFIG_ENTRY_END
    li      t0, CONFIG_BLOB_SCHEDULE_MAX
    bgeu    s9, t0, 89f
    addi    s9, s9, 1
    li      s10, 4
    sd      s5, L(sp)
    ld      t3, (L + 72)(sp)
    sd      t3, (L + 8)(sp)
    ld      t0, (L + 80)(sp)
53: lbu     t1, 0(t0)
    li      t2, 0x20
    bne     t1, t2, 56f
    addi    t0, t0, 1
    j       53b
55: andi    t1, s10, 4                      # a field of the open entry, past its dash
    beqz    t1, 89f
    ld      t2, (L + 8)(sp)
    bleu    t3, t2, 89f
56: mv      t1, t0                          # FIELD: and spaces and a value
57: bgeu    t1, s8, 89f
    lbu     t2, 0(t1)
    li      t3, 0x3a
    beq     t2, t3, 58f
    addi    t1, t1, 1
    j       57b
58: sub     t4, t1, t0                      # the field's length
    addi    t1, t1, 1
    bgeu    t1, s8, 89f
    lbu     t2, 0(t1)
    li      t3, 0x20
    bne     t2, t3, 89f
581: lbu    t2, 0(t1)
    bne     t2, t3, 582f
    addi    t1, t1, 1
    j       581b
582: sd     t0, (L + 40)(sp)
    sd      t4, (L + 48)(sp)
    sd      t1, (L + 56)(sp)
    mv      a0, t0
    mv      a1, t4
    ADDRESS a2, config_epoch_name
    li      a3, 5
    call    config_name_is
    li      t0, 1                           # EPOCH: bit 0
    bnez    a0, 59f
    ld      a0, (L + 40)(sp)
    ld      a1, (L + 48)(sp)
    ADDRESS a2, config_max_name
    li      a3, 19
    call    config_name_is
    beqz    a0, 89f
    li      t0, 2                           # MAX_BLOBS_PER_BLOCK: bit 1
59: and     t1, s10, t0
    bnez    t1, 89f                         # given twice
    or      s10, s10, t0
    sd      t0, (L + 64)(sp)
    ld      a0, (L + 56)(sp)
    mv      a1, s8
    call    config_unquote
    bnez    a0, 89f
    mv      a0, a1
    mv      a1, a2
    call    config_u64
    bnez    a0, 89f
    ld      t0, (L + 64)(sp)                # L+16 or L+24
    slli    t0, t0, 3
    add     t0, t0, sp
    sd      a1, (L + 8)(t0)
    j       10b
90: CONFIG_ENTRY_END                        # the end of the text
    beqz    s2, 95f
    ld      t0, (L + 32)(sp)                # the schedule's count, then its entries sorted by EPOCH
    beqz    t0, 95f
    sd      s9, CONFIG_BLOB_SCHEDULE_COUNT(s1)
    addi    t0, s1, CONFIG_BLOB_SCHEDULE
    li      t1, 1
91: bgeu    t1, s9, 95f
    slli    t2, t1, 4                       # the place of entry t1
    add     t2, t2, t0
    ld      t3, 0(t2)
    ld      t4, 8(t2)
92: bleu    t2, t0, 93f
    ld      t5, -16(t2)
    bleu    t5, t3, 93f                     # an equal EPOCH stays before
    sd      t5, 0(t2)
    ld      t6, -8(t2)
    sd      t6, 8(t2)
    addi    t2, t2, -16
    j       92b
93: sd      t3, 0(t2)
    sd      t4, 8(t2)
    addi    t1, t1, 1
    j       91b
95: li      a0, 0
    LEAVE 96
80: ld      s5, L(sp)                       # the line of the open entry
89: mv      a0, s5
    LEAVE 96
END_FUNCTION config_scan

/* (text, config, line): docs/reference/config.md. s1 text, s2 config, s3 line. */
FUNCTION lantern_config_parse
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    li      a2, 0                           # check every line first
    call    config_scan
    bnez    a0, 1f
    mv      a0, s1
    mv      a1, s2
    li      a2, 1
    call    config_scan
    sd      zero, 0(s3)
    li      a0, LANTERN_OK
    LEAVE 0
1:  sd      a0, 0(s3)
    li      a0, LANTERN_INVALID_CONFIG
    LEAVE 0
END_FUNCTION lantern_config_parse
