/*
 * The command line options of the binary, ARM64: in the common object. Requirements: docs/reference/app.md, lantern_app_options.
 */

    RODATA
.include "app_options.inc"

/* x0 = 0 and x1 = the u64 of the decimal digits x0 to x1, one or more; else x0 = 1. Uses x9-x12. */
LOCAL_FUNCTION lantern_app_decimal
    UNWIND_END_PROLOGUE
    cmp     x0, x1
    b.hs    9f
    mov     x9, #0
1:  cmp     x0, x1
    b.hs    8f
    ldrb    w10, [x0], #1
    sub     w10, w10, #0x30
    cmp     w10, #9
    b.hi    9f
    mov     x11, #10
    umulh   x12, x9, x11
    cbnz    x12, 9f
    mul     x9, x9, x11
    adds    x9, x9, x10
    b.cs    9f
    b       1b
8:  mov     x1, x9
    mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION lantern_app_decimal

/*
 * x0 = 0 and x1 = the IPv4 address of the bytes x0 to x1, 4 decimal numbers of 0 to 255 with
 * dots between them, its 4 bytes in order in the low bytes; else x0 = 1. Uses x9-x14.
 */
LOCAL_FUNCTION lantern_app_ipv4
    UNWIND_END_PROLOGUE
    mov     x9, #0                          /* the address */
    mov     x10, #0                         /* the numbers */
    mov     x13, #0                         /* the shift of the next one */
1:  mov     x11, #0                         /* a number */
    mov     x12, #0                         /* its digits */
2:  cmp     x0, x1
    b.hs    3f
    ldrb    w14, [x0]
    cmp     w14, #0x2e                      /* . */
    b.eq    3f
    sub     w14, w14, #0x30
    cmp     w14, #9
    b.hi    9f
    add     x12, x12, #1
    cmp     x12, #3
    b.hi    9f
    add     x11, x11, x11, lsl #2
    lsl     x11, x11, #1
    add     x11, x11, x14
    add     x0, x0, #1
    b       2b
3:  cbz     x12, 9f
    cmp     x11, #255
    b.hi    9f
    lsl     x11, x11, x13
    orr     x9, x9, x11
    add     x13, x13, #8
    add     x10, x10, #1
    cmp     x0, x1
    b.hs    4f
    add     x0, x0, #1                      /* past the dot, to the next number */
    cmp     x10, #4
    b.hs    9f
    b       1b
4:  cmp     x10, #4
    b.ne    9f
    mov     x1, x9
    mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION lantern_app_ipv4

/*
 * x0 = 0 and x1 = the bits of the metrics categories x0 to x1, names of app_categories_table
 * with commas between them, none or more; else x0 = 1. Uses x9-x15.
 */
LOCAL_FUNCTION lantern_app_categories
    UNWIND_END_PROLOGUE
    mov     x9, #0                          /* the bits */
    cmp     x0, x1
    b.eq    8f                              /* no category */
1:  mov     x10, x0                         /* a name: up to a comma or the end */
2:  cmp     x10, x1
    b.hs    3f
    ldrb    w11, [x10]
    cmp     w11, #0x2c                      /* , */
    b.eq    3f
    add     x10, x10, #1
    b       2b
3:  subs    x11, x10, x0                    /* its length: 1 or more */
    b.eq    9f
    ADDRESS x12, app_categories_table
4:  ADDRESS x13, app_categories_end
    cmp     x12, x13
    b.hs    9f                              /* not a category */
    ldr     x13, [x12, #8]
    cmp     x13, x11
    b.ne    6f
    mov     x13, #0
5:  ldrb    w14, [x0, x13]
    add     x15, x12, #16
    ldrb    w15, [x15, x13]
    cmp     w14, w15
    b.ne    6f
    add     x13, x13, #1
    cmp     x13, x11
    b.lo    5b
    ldr     x13, [x12]
    orr     x9, x9, x13
    cmp     x10, x1                         /* the next name, past the comma */
    b.hs    8f
    add     x0, x10, #1
    b       1b
6:  add     x12, x12, #APP_CATEGORY_BYTES
    b       4b
8:  mov     x1, x9
    mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION lantern_app_categories

/*
 * (args, options, fault): docs/reference/app.md. x19 args, x20 options, x21 fault, x22 the
 * argument count, x23 the next argument, x24 the Arg entries, x25 an option record, x26 the
 * value's start, x27 its length, x28 the argument that holds it. Locals: L the name's start,
 * L+8 its length, L+16 the option's argument, L+24 a log level.
 */
FUNCTION lantern_app_options
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x0, x20                         /* the defaults */
    mov     x1, #AppOptions__size
    bl      lantern_zero
    mov     x9, #APP_DEFAULT_PORT
    str     x9, [x20, #AppOptions_port]
    mov     x9, #APP_DEFAULT_HTTP_PORT
    str     x9, [x20, #AppOptions_http_port]
    mov     x9, #APP_DEFAULT_TARGET_PEERS
    str     x9, [x20, #AppOptions_target_peers]
    mov     x9, #APP_DEFAULT_LOG_LEVEL
    str     x9, [x20, #AppOptions_log_level]
    MOVQ    x9, APP_DEFAULT_HTTP_ADDRESS
    str     x9, [x20, #AppOptions_http_address]
    mov     x9, #APP_DEFAULT_HTTP_CONNECTIONS
    str     x9, [x20, #AppOptions_http_max_connections]
    mov     x9, #APP_DEFAULT_METRICS
    str     x9, [x20, #AppOptions_metrics]
    MOVQ    x9, APP_DEFAULT_METRICS_ADDRESS
    str     x9, [x20, #AppOptions_metrics_address]
    mov     x9, #APP_DEFAULT_METRICS_PORT
    str     x9, [x20, #AppOptions_metrics_port]
    ldr     x22, [x19, #(ArgList_args + 8)]
    ldr     x9, [x19, #ArgList_args]
    add     x24, x19, x9
    mov     x23, #0
1:  cmp     x23, x22                        /* the next option: --name value or --name=value */
    b.hs    50f
    str     x23, [sp, #(L + 16)]
    mov     x28, x23
    add     x9, x24, x23, lsl #4
    ldp     x10, x11, [x9]
    cmp     x11, #3
    b.lo    91f
    add     x12, x19, x10
    ldrb    w13, [x12]
    ldrb    w14, [x12, #1]
    cmp     w13, #0x2d
    b.ne    91f
    cmp     w14, #0x2d
    b.ne    91f
    add     x10, x10, #2
    sub     x11, x11, #2
    str     x10, [sp, #L]
    add     x12, x19, x10
    mov     x13, #0
2:  cmp     x13, x11                        /* the name: up to = or the end */
    b.hs    3f
    ldrb    w14, [x12, x13]
    cmp     w14, #0x3d                      /* = */
    b.eq    3f
    add     x13, x13, #1
    b       2b
3:  str     x13, [sp, #(L + 8)]
    mov     x26, x13                        /* x26: where = is, x27: the length of the name and value */
    mov     x27, x11
    ADDRESS x25, app_options
6:  ADDRESS x9, app_options_end
    cmp     x25, x9
    b.hs    91f                             /* not an option */
    ldp     x0, x1, [sp, #L]
    add     x0, x19, x0
    add     x2, x25, #24
    ldr     x3, [x25]
    bl      lantern_config_name_is
    cbnz    x0, 4f
    add     x25, x25, #APP_OPTION_BYTES
    b       6b
4:  ldr     x9, [x25, #16]
    cmp     x9, #APP_OPTION_FLAG
    b.ne    5f
    cmp     x26, x27                        /* a flag: no value, 1 */
    b.ne    90f
    add     x23, x23, #1
    mov     x1, #1
    b       23f
5:  cmp     x26, x27
    b.ne    51f
    add     x28, x23, #1                    /* --name value: the value is the next argument */
    cmp     x28, x22
    b.hs    91f
    add     x9, x24, x28, lsl #4
    ldp     x26, x27, [x9]
    add     x23, x23, #2
    b       7f
51: ldr     x10, [sp, #L]                   /* --name=value */
    add     x10, x10, x26
    add     x10, x10, #1
    sub     x27, x27, x26
    sub     x27, x27, #1
    mov     x26, x10
    add     x23, x23, #1
7:  ldr     x9, [x25, #16]
    cmp     x9, #APP_OPTION_CATEGORIES
    b.eq    27f
    cbz     x27, 90f                        /* an empty value */
    cmp     x9, #APP_OPTION_ENDPOINT
    b.hi    20f
    b.ne    8f
    cmp     x27, #7                         /* the endpoint: without http:// */
    b.lo    8f
    add     x0, x19, x26
    mov     x1, #7
    ADDRESS x2, app_http
    mov     x3, #7
    bl      lantern_config_name_is
    cbz     x0, 8f
    add     x26, x26, #7
    sub     x27, x27, #7
    cbz     x27, 90f
8:  ldr     x10, [x25, #8]                  /* a text: its Arg */
    add     x10, x20, x10
    stp     x26, x27, [x10]
    b       1b
20: cmp     x9, #APP_OPTION_LEVEL
    b.eq    24f
    add     x0, x19, x26                    /* a number, or an address */
    add     x1, x0, x27
    cmp     x9, #APP_OPTION_ADDRESS
    b.eq    21f
    bl      lantern_app_decimal
    cbnz    x0, 90f
    cbz     x1, 90f
    ldr     x9, [x25, #16]
    mov     x10, #65535
    cmp     x9, #APP_OPTION_PORT
    b.eq    22f
    mov     x10, #APP_MAX_TARGET_PEERS
    cmp     x9, #APP_OPTION_CONNECTIONS
    b.ne    22f
    mov     x10, #APP_MAX_HTTP_CONNECTIONS
22: cmp     x1, x10
    b.hi    90f
    b       23f
21: bl      lantern_app_ipv4
    cbnz    x0, 90f
23: ldr     x10, [x25, #8]
    str     x1, [x20, x10]
    b       1b
24: str     xzr, [sp, #(L + 24)]            /* a log level: one of the names of app_levels */
25: ldr     x9, [sp, #(L + 24)]
    cmp     x9, #4
    b.hs    90f
    ADDRESS x2, app_levels
    add     x2, x2, x9, lsl #3
    ADDRESS x3, app_level_lengths
    ldrb    w3, [x3, x9]
    add     x0, x19, x26
    mov     x1, x27
    bl      lantern_config_name_is
    cbnz    x0, 26f
    ldr     x9, [sp, #(L + 24)]
    add     x9, x9, #1
    str     x9, [sp, #(L + 24)]
    b       25b
26: ldr     x1, [sp, #(L + 24)]
    b       23b
27: add     x0, x19, x26                    /* metrics categories: their bits; an empty value has none */
    add     x1, x0, x27
    bl      lantern_app_categories
    cbnz    x0, 90f
    b       23b
50: ldr     x9, [x20, #(AppOptions_network_dir + 8)]    /* --network-dir is required */
    mov     x28, x22
    cbz     x9, 90f
    ldr     x9, [x20, #(AppOptions_checkpoint_state + 8)]   /* --checkpoint-state and --checkpoint-block go together */
    ldr     x10, [x20, #(AppOptions_checkpoint_block + 8)]
    cmp     x9, #0
    cset    x9, eq
    cmp     x10, #0
    cset    x10, eq
    cmp     x9, x10
    b.ne    90f
    ldr     x9, [x20, #AppOptions_archive]  /* --archive needs --data-dir */
    cbz     x9, 51f
    ldr     x9, [x20, #(AppOptions_data_dir + 8)]
    cbz     x9, 90f
51: str     xzr, [x21]
    mov     x0, #LANTERN_OK
    LEAVE 32
91: ldr     x28, [sp, #(L + 16)]            /* a fault of the option's argument */
90: str     x28, [x21]                      /* a fault of the value's argument */
    mov     x0, #LANTERN_INVALID_OPTION
    LEAVE 32
END_FUNCTION lantern_app_options
