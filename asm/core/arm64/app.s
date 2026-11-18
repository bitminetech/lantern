/*
 * The application, ARM64: in the common object. Requirements: docs/reference/app.md.
 */

    RODATA
.include "app_options.inc"

/* L0: x0 = 0 and x1 = the u64 of the decimal digits x0 to x1, one or more; else x0 = 1. Uses x9-x12. */
LOCAL_FUNCTION app_decimal
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
END_FUNCTION app_decimal

/*
 * L0: x0 = 0 and x1 = the IPv4 address of the bytes x0 to x1, 4 decimal numbers of 0 to 255 with
 * dots between them, its 4 bytes in order in the low bytes; else x0 = 1. Uses x9-x14.
 */
LOCAL_FUNCTION app_ipv4
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
END_FUNCTION app_ipv4

/*
 * (args, options, fault): docs/reference/app.md. x19 args, x20 options, x21 fault, x22 the
 * argument count, x23 the next argument, x24 the Arg entries, x25 an option record, x26 the
 * value's start, x27 its length, x28 the argument that holds it. Locals: L the name's start,
 * L+8 its length, L+16 the option's argument.
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
2:  cmp     x13, x11
    b.hs    3f
    ldrb    w14, [x12, x13]
    cmp     w14, #0x3d                      /* = */
    b.eq    4f
    add     x13, x13, #1
    b       2b
3:  str     x11, [sp, #(L + 8)]             /* --name value: the value is the next argument */
    add     x28, x23, #1
    cmp     x28, x22
    b.hs    91f
    add     x9, x24, x28, lsl #4
    ldp     x26, x27, [x9]
    add     x23, x23, #2
    b       5f
4:  str     x13, [sp, #(L + 8)]             /* --name=value */
    add     x26, x10, x13
    add     x26, x26, #1
    sub     x27, x11, x13
    sub     x27, x27, #1
    add     x23, x23, #1
5:  ADDRESS x25, app_options
6:  ADDRESS x9, app_options_end
    cmp     x25, x9
    b.hs    91f                             /* not an option */
    ldp     x0, x1, [sp, #L]
    add     x0, x19, x0
    add     x2, x25, #24
    ldr     x3, [x25]
    bl      config_name_is
    cbnz    x0, 7f
    add     x25, x25, #APP_OPTION_BYTES
    b       6b
7:  cbz     x27, 90f                        /* an empty value */
    ldr     x9, [x25, #16]
    cmp     x9, #APP_OPTION_ENDPOINT
    b.hi    20f
    b.ne    8f
    cmp     x27, #7                         /* the endpoint: without http:// */
    b.lo    8f
    add     x0, x19, x26
    mov     x1, #7
    ADDRESS x2, app_http
    mov     x3, #7
    bl      config_name_is
    cbz     x0, 8f
    add     x26, x26, #7
    sub     x27, x27, #7
    cbz     x27, 90f
8:  ldr     x10, [x25, #8]                  /* a text: its Arg */
    add     x10, x20, x10
    stp     x26, x27, [x10]
    b       1b
20: add     x0, x19, x26                    /* a number, or an address */
    add     x1, x0, x27
    cmp     x9, #APP_OPTION_ADDRESS
    b.eq    21f
    bl      app_decimal
    cbnz    x0, 90f
    cbz     x1, 90f
    ldr     x9, [x25, #16]
    mov     x10, #65535
    cmp     x9, #APP_OPTION_PORT
    b.eq    22f
    mov     x10, #APP_MAX_TARGET_PEERS
22: cmp     x1, x10
    b.hi    90f
    b       23f
21: bl      app_ipv4
    cbnz    x0, 90f
23: ldr     x10, [x25, #8]
    str     x1, [x20, x10]
    b       1b
50: ldr     x9, [x20, #(AppOptions_network_dir + 8)]    /* --network-dir is required */
    mov     x28, x22
    cbz     x9, 90f
    str     xzr, [x21]
    mov     x0, #LANTERN_OK
    LEAVE 32
91: ldr     x28, [sp, #(L + 16)]            /* a fault of the option's argument */
90: str     x28, [x21]                      /* a fault of the value's argument */
    mov     x0, #LANTERN_INVALID_OPTION
    LEAVE 32
END_FUNCTION lantern_app_options
