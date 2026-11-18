/*
 * The network config file, ARM64: in the common object. Requirements: docs/reference/config.md.
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

/* \out = the value of the hex digit in \in (w registers), or 16 when it is not one. */
.macro CONFIG_HEX out, in
    sub     \out, \in, #0x30
    cmp     \out, #10
    b.lo    91f
    orr     \out, \in, #0x20                /* a to f, either case */
    sub     \out, \out, #0x61
    cmp     \out, #6
    add     \out, \out, #10
    b.lo    91f
    mov     \out, #16
91:
.endm

/* L0: x0 = 1 when the x1 bytes at x0 are the x3 bytes at x2, else 0. Uses x9, x10. */
LOCAL_FUNCTION config_name_is
    UNWIND_END_PROLOGUE
    cmp     x1, x3
    b.ne    2f
1:  cbz     x1, 3f
    ldrb    w9, [x0], #1
    ldrb    w10, [x2], #1
    cmp     w9, w10
    b.ne    2f
    sub     x1, x1, #1
    b       1b
2:  mov     x0, #0
    ret
3:  mov     x0, #1
    ret
END_FUNCTION config_name_is

/* L0: the value bytes x0 to x1 without a pair of quotes: x0 = 0, x1 their start, x2 their end; x0 = 1 for a quote with no end. Uses x9, x10. */
LOCAL_FUNCTION config_unquote
    UNWIND_END_PROLOGUE
    mov     x2, x1
    mov     x1, x0
    cmp     x1, x2
    b.hs    8f
    ldrb    w9, [x1]
    cmp     w9, #0x27                       /* ' */
    b.eq    1f
    cmp     w9, #0x22                       /* " */
    b.ne    8f
1:  sub     x10, x2, x1
    cmp     x10, #2
    b.lo    9f
    ldrb    w10, [x2, #-1]
    cmp     w10, w9
    b.ne    9f
    add     x1, x1, #1
    sub     x2, x2, #1
8:  mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION config_unquote

/* L0: x0 = 0 and x1 = the u64 of the bytes x0 to x1: decimal, or 0x and 1 to 16 hex digits; else x0 = 1. Uses x9-x13. */
LOCAL_FUNCTION config_u64
    UNWIND_END_PROLOGUE
    sub     x9, x1, x0
    cbz     x9, 9f
    mov     x10, #0                         /* the value */
    cmp     x9, #3
    b.lo    3f
    ldrb    w11, [x0]
    ldrb    w12, [x0, #1]
    cmp     w11, #0x30                      /* 0x */
    b.ne    3f
    cmp     w12, #0x78
    b.ne    3f
    sub     x9, x9, #2
    cmp     x9, #16
    b.hi    9f
    add     x0, x0, #2
2:  cmp     x0, x1
    b.hs    8f
    ldrb    w11, [x0], #1
    CONFIG_HEX w12, w11
    cmp     w12, #16
    b.hs    9f
    orr     x10, x12, x10, lsl #4
    b       2b
3:  cmp     x0, x1                          /* decimal */
    b.hs    8f
    ldrb    w11, [x0], #1
    sub     w11, w11, #0x30
    cmp     w11, #9
    b.hi    9f
    mov     x12, #10
    umulh   x13, x10, x12
    cbnz    x13, 9f
    mul     x10, x10, x12
    adds    x10, x10, x11
    b.cs    9f
    b       3b
8:  mov     x1, x10
    mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION config_u64

/* L0: x0 = 0 when the bytes x0 to x1 are 0x and 2 * x3 hex digits, whose x3 bytes go to x2 in order; else 1. Uses x9-x12. */
LOCAL_FUNCTION config_hex_bytes
    UNWIND_END_PROLOGUE
    sub     x9, x1, x0
    lsl     x10, x3, #1
    add     x10, x10, #2
    cmp     x9, x10
    b.ne    9f
    ldrb    w9, [x0]
    ldrb    w10, [x0, #1]
    cmp     w9, #0x30                       /* 0x */
    b.ne    9f
    cmp     w10, #0x78
    b.ne    9f
    add     x0, x0, #2
1:  cbz     x3, 8f
    ldrb    w9, [x0], #1
    CONFIG_HEX w10, w9
    cmp     w10, #16
    b.hs    9f
    ldrb    w9, [x0], #1
    CONFIG_HEX w11, w9
    cmp     w11, #16
    b.hs    9f
    orr     w10, w11, w10, lsl #4
    strb    w10, [x2], #1
    sub     x3, x3, #1
    b       1b
8:  mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION config_hex_bytes

/* L0: x0 = 0 when the bytes x0 to x1 are the decimal digits of a number below 2^256, then little endian at x2 (32 bytes); else 1. Uses x9-x14. */
LOCAL_FUNCTION config_uint256
    UNWIND_END_PROLOGUE
    stp     xzr, xzr, [x2]
    stp     xzr, xzr, [x2, #16]
    cmp     x0, x1
    b.hs    9f
1:  cmp     x0, x1
    b.hs    8f
    ldrb    w9, [x0], #1                    /* the carry: the digit */
    sub     w9, w9, #0x30
    cmp     w9, #9
    b.hi    9f
    mov     x10, #10
    mov     x11, #0                         /* each limb: limb * 10 + carry */
2:  ldr     x12, [x2, x11]
    mul     x13, x12, x10
    umulh   x14, x12, x10
    adds    x13, x13, x9
    adc     x9, x14, xzr
    str     x13, [x2, x11]
    add     x11, x11, #8
    cmp     x11, #32
    b.lo    2b
    cbnz    x9, 9f                          /* 2^256 or more */
    b       1b
8:  mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION config_uint256

/*
 * L1: x0 = 0 when the value bytes x1 to x2, without a pair of quotes, are a value of the kind
 * x0, then at x3: 8 bytes (u64; Version: 4 bytes and 4 zero bytes) or 32 (Uint256, Hash32);
 * else 1. x19 the kind, x20 out.
 */
LOCAL_FUNCTION config_value
    ENTER 0
    mov     x19, x0
    mov     x20, x3
    mov     x0, x1
    mov     x1, x2
    bl      config_unquote
    cbnz    x0, 9f
    mov     x0, x1
    mov     x1, x2
    cmp     x19, #CONFIG_KIND_U64
    b.ne    1f
    bl      config_u64
    cbnz    x0, 9f
    str     x1, [x20]
    b       9f
1:  cmp     x19, #CONFIG_KIND_VERSION
    b.ne    2f
    str     xzr, [x20]
    mov     x2, x20
    mov     x3, #4
    bl      config_hex_bytes
    b       9f
2:  cmp     x19, #CONFIG_KIND_UINT256
    b.ne    3f
    mov     x2, x20
    bl      config_uint256
    b       9f
3:  mov     x2, x20                         /* Hash32 */
    mov     x3, #32
    bl      config_hex_bytes
9:  LEAVE 0
END_FUNCTION config_value

/*
 * In config_scan: close the open entry of the schedule: to 80f (a fault at its line) without
 * both fields; else with write, its EPOCH and MAX_BLOBS_PER_BLOCK as schedule entry x27 - 1. Uses x9-x12.
 */
.macro CONFIG_ENTRY_END
    tbz     x28, #2, 99f
    and     x9, x28, #3
    cmp     x9, #3
    b.ne    80f
    cbz     x20, 98f
    sub     x9, x27, #1
    add     x10, x19, #CONFIG_BLOB_SCHEDULE
    add     x10, x10, x9, lsl #4
    ldp     x11, x12, [sp, #(L + 16)]
    stp     x11, x12, [x10]
98: mov     x28, #0
99:
.endm

.set CONFIG_MODE_NONE, 0                    /* no key yet */
.set CONFIG_MODE_SCALAR, 1                  /* a key lantern reads, or BLOB_SCHEDULE: [] */
.set CONFIG_MODE_SKIP, 2                    /* a key lantern does not read */
.set CONFIG_MODE_SCHEDULE, 3                /* the entries of BLOB_SCHEDULE */

/*
 * L1: x0 = 0, or the number of the first faulty line, of the config text x0 (a ByteList); with
 * x2 = 1, writes its values into the config x1. x19 config, x20 write, x21 the next line, x22 the
 * text end, x23 the line number, x24 the mode or a key record, x25 the line start, x26 the line
 * end, x27 the schedule's entries, x28 the open entry: bit 0 EPOCH, bit 1 MAX_BLOBS_PER_BLOCK,
 * bit 2 open. Locals: L the entry's line, L+8 its dash column, L+16 its EPOCH, L+24 its
 * MAX_BLOBS_PER_BLOCK, L+32 1 when the text gives BLOB_SCHEDULE, L+40 a value (32 bytes) or a
 * field, L+72 the value's start, L+80 the key's length.
 */
LOCAL_FUNCTION config_scan
    ENTER 96
    mov     x19, x1
    mov     x20, x2
    ldr     x9, [x0, #8]
    add     x21, x0, x9
    ldr     x9, [x0, #16]
    add     x22, x21, x9
    mov     x23, #0
    mov     x24, #CONFIG_MODE_NONE
    mov     x27, #0
    mov     x28, #0
    str     xzr, [sp, #(L + 32)]
10: cmp     x21, x22                        /* the next line */
    b.hs    90f
    add     x23, x23, #1
    mov     x25, x21
11: cmp     x21, x22                        /* its end: an LF or the text end */
    b.hs    12f
    ldrb    w9, [x21]
    cmp     w9, #10
    b.eq    12f
    add     x21, x21, #1
    b       11b
12: mov     x26, x21
    cmp     x21, x22
    b.hs    13f
    add     x21, x21, #1                    /* past the LF, and a CR before it */
    cmp     x26, x25
    b.ls    13f
    ldrb    w9, [x26, #-1]
    cmp     w9, #13
    b.ne    13f
    sub     x26, x26, #1
13: mov     x9, x25                         /* a comment: # at the start or after a space or tab, outside quotes */
    mov     w10, #0                         /* the open quote */
14: cmp     x9, x26
    b.hs    17f
    ldrb    w11, [x9]
    cbz     w10, 15f
    cmp     w11, w10
    b.ne    16f
    mov     w10, #0
    b       16f
15: cmp     w11, #0x27
    b.eq    151f
    cmp     w11, #0x22
    b.ne    152f
151: mov    w10, w11
    b       16f
152: cmp    w11, #0x23                      /* # */
    b.ne    16f
    cmp     x9, x25
    b.eq    153f
    ldrb    w12, [x9, #-1]
    cmp     w12, #0x20
    b.eq    153f
    cmp     w12, #9
    b.ne    16f
153: mov    x26, x9
    b       17f
16: add     x9, x9, #1
    b       14b
17: cmp     x26, x25                        /* the spaces and tabs at the end */
    b.ls    10b                             /* an empty line */
    ldrb    w9, [x26, #-1]
    cmp     w9, #0x20
    b.eq    171f
    cmp     w9, #9
    b.ne    18f
171: sub    x26, x26, #1
    b       17b
18: sub     x9, x26, x25                    /* --- */
    cmp     x9, #3
    b.ne    19f
    ldrb    w10, [x25]
    ldrb    w11, [x25, #1]
    ldrb    w12, [x25, #2]
    cmp     w10, #0x2d
    b.ne    19f
    cmp     w11, #0x2d
    b.ne    19f
    cmp     w12, #0x2d
    b.eq    10b
19: ldrb    w9, [x25]
    cmp     w9, #0x20
    b.eq    50f
    CONFIG_ENTRY_END                        /* KEY: and nothing, or spaces and a value */
    mov     x9, x25
21: cmp     x9, x26
    b.hs    89f
    ldrb    w10, [x9]
    cmp     w10, #0x3a                      /* : */
    b.eq    23f
    sub     w11, w10, #0x30                 /* 0 to 9, _, A to Z, a to z */
    cmp     w11, #10
    b.lo    22f
    cmp     w10, #0x5f
    b.eq    22f
    orr     w11, w10, #0x20
    sub     w11, w11, #0x61
    cmp     w11, #26
    b.hs    89f
22: add     x9, x9, #1
    b       21b
23: sub     x12, x9, x25
    cbz     x12, 89f
    str     x12, [sp, #(L + 80)]
    add     x9, x9, #1
    cmp     x9, x26
    b.hs    25f
    ldrb    w10, [x9]
    cmp     w10, #0x20
    b.ne    89f
24: ldrb    w10, [x9]                       /* the spaces before the value */
    cmp     w10, #0x20
    b.ne    25f
    add     x9, x9, #1
    b       24b
25: str     x9, [sp, #(L + 72)]
    mov     x0, x25
    mov     x1, x12
    ADDRESS x2, config_schedule_name
    mov     x3, #13
    bl      config_name_is
    cbnz    x0, 30f
    ADDRESS x24, config_keys
26: ADDRESS x9, config_keys_end
    cmp     x24, x9
    b.hs    27f
    mov     x0, x25
    ldr     x1, [sp, #(L + 80)]
    add     x2, x24, #24
    ldr     x3, [x24]
    bl      config_name_is
    cbnz    x0, 28f
    add     x24, x24, #CONFIG_KEY_BYTES
    b       26b
27: mov     x24, #CONFIG_MODE_SKIP          /* a key lantern does not read */
    b       10b
28: ldr     x0, [x24, #16]                  /* a key lantern reads */
    ldr     x1, [sp, #(L + 72)]
    mov     x2, x26
    add     x3, sp, #(L + 40)
    bl      config_value
    cbnz    x0, 89f
    cbz     x20, 29f
    ldr     x9, [x24, #8]                   /* 8 bytes, or 32 for a Uint256 or a Hash32 */
    add     x9, x19, x9
    ldr     x10, [x24, #16]
    ldp     x11, x12, [sp, #(L + 40)]
    cmp     x10, #CONFIG_KIND_VERSION
    b.hi    281f
    str     x11, [x9]
    b       29f
281: stp    x11, x12, [x9]
    ldp     x11, x12, [sp, #(L + 56)]
    stp     x11, x12, [x9, #16]
29: mov     x24, #CONFIG_MODE_SCALAR
    b       10b
30: mov     x27, #0                         /* BLOB_SCHEDULE: nothing, then its entries; or [] */
    mov     x9, #1
    str     x9, [sp, #(L + 32)]
    mov     x24, #CONFIG_MODE_SCHEDULE
    ldr     x9, [sp, #(L + 72)]
    cmp     x9, x26
    b.hs    10b
    sub     x10, x26, x9
    cmp     x10, #2
    b.ne    89f
    ldrb    w10, [x9]
    ldrb    w11, [x9, #1]
    cmp     w10, #0x5b
    b.ne    89f
    cmp     w11, #0x5d
    b.ne    89f
    mov     x24, #CONFIG_MODE_SCALAR
    b       10b
50: cmp     x24, #CONFIG_MODE_SKIP          /* an indented line */
    b.eq    10b
    cmp     x24, #CONFIG_MODE_SCHEDULE
    b.ne    89f
    mov     x9, x25
51: ldrb    w10, [x9]
    cmp     w10, #0x20
    b.ne    52f
    add     x9, x9, #1
    b       51b
52: sub     x11, x9, x25                    /* its column */
    cmp     w10, #0x2d
    b.ne    55f
    add     x12, x9, #1                     /* - and a space: a new entry */
    cmp     x12, x26
    b.hs    89f
    ldrb    w10, [x12]
    cmp     w10, #0x20
    b.ne    89f
    stp     x11, x12, [sp, #(L + 72)]
    CONFIG_ENTRY_END
    cmp     x27, #CONFIG_BLOB_SCHEDULE_MAX
    b.hs    89f
    add     x27, x27, #1
    mov     x28, #4
    str     x23, [sp, #L]
    ldp     x11, x9, [sp, #(L + 72)]
    str     x11, [sp, #(L + 8)]
53: ldrb    w10, [x9]
    cmp     w10, #0x20
    b.ne    56f
    add     x9, x9, #1
    b       53b
55: tbz     x28, #2, 89f                    /* a field of the open entry, past its dash */
    ldr     x12, [sp, #(L + 8)]
    cmp     x11, x12
    b.ls    89f
56: mov     x10, x9                         /* FIELD: and spaces and a value */
57: cmp     x10, x26
    b.hs    89f
    ldrb    w11, [x10]
    cmp     w11, #0x3a
    b.eq    58f
    add     x10, x10, #1
    b       57b
58: sub     x11, x10, x9
    add     x12, x10, #1
    cmp     x12, x26
    b.hs    89f
    ldrb    w13, [x12]
    cmp     w13, #0x20
    b.ne    89f
581: ldrb   w13, [x12]
    cmp     w13, #0x20
    b.ne    582f
    add     x12, x12, #1
    b       581b
582: stp    x9, x11, [sp, #(L + 40)]
    str     x12, [sp, #(L + 56)]
    mov     x0, x9
    mov     x1, x11
    ADDRESS x2, config_epoch_name
    mov     x3, #5
    bl      config_name_is
    mov     x9, #1                          /* EPOCH: bit 0 */
    cbnz    x0, 59f
    ldp     x0, x1, [sp, #(L + 40)]
    ADDRESS x2, config_max_name
    mov     x3, #19
    bl      config_name_is
    cbz     x0, 89f
    mov     x9, #2                          /* MAX_BLOBS_PER_BLOCK: bit 1 */
59: tst     x28, x9
    b.ne    89f                             /* given twice */
    orr     x28, x28, x9
    str     x9, [sp, #(L + 64)]
    ldr     x0, [sp, #(L + 56)]
    mov     x1, x26
    bl      config_unquote
    cbnz    x0, 89f
    mov     x0, x1
    mov     x1, x2
    bl      config_u64
    cbnz    x0, 89f
    ldr     x9, [sp, #(L + 64)]
    add     x10, sp, #(L + 8)
    str     x1, [x10, x9, lsl #3]           /* L+16 or L+24 */
    b       10b
90: CONFIG_ENTRY_END                        /* the end of the text */
    cbz     x20, 95f
    ldr     x9, [sp, #(L + 32)]             /* the schedule's count, then its entries sorted by EPOCH */
    cbz     x9, 95f
    str     x27, [x19, #CONFIG_BLOB_SCHEDULE_COUNT]
    add     x10, x19, #CONFIG_BLOB_SCHEDULE
    mov     x9, #1
91: cmp     x9, x27
    b.hs    95f
    add     x14, x10, x9, lsl #4            /* the place of entry x9 */
    ldp     x11, x12, [x14]
92: cmp     x14, x10
    b.ls    93f
    ldp     x15, x16, [x14, #-16]
    cmp     x15, x11
    b.ls    93f                             /* an equal EPOCH stays before */
    stp     x15, x16, [x14]
    sub     x14, x14, #16
    b       92b
93: stp     x11, x12, [x14]
    add     x9, x9, #1
    b       91b
95: mov     x0, #0
    LEAVE 96
80: ldr     x23, [sp, #L]                   /* the line of the open entry */
89: mov     x0, x23
    LEAVE 96
END_FUNCTION config_scan

/* (text, config, line): docs/reference/config.md. x19 text, x20 config, x21 line. */
FUNCTION lantern_config_parse
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x2, #0                          /* check every line first */
    bl      config_scan
    cbnz    x0, 1f
    mov     x0, x19
    mov     x1, x20
    mov     x2, #1
    bl      config_scan
    str     xzr, [x21]
    mov     x0, #LANTERN_OK
    LEAVE 0
1:  str     x0, [x21]
    mov     x0, #LANTERN_INVALID_CONFIG
    LEAVE 0
END_FUNCTION lantern_config_parse
