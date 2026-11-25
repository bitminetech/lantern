/*
 * Metrics, ARM64: in the common object. Requirements: docs/reference/metrics.md.
 *
 * The writers keep the cursor in x20 and the end of the room in x21; x22 becomes 1 when the room
 * runs out, and nothing is written from then on. x19 holds metrics_texts. A LabelState (LS_*) holds
 * the label tables of a family and the element's value index in each. No comment stands on the
 * line of a macro (Apple's assembler reads its commas as arguments).
 */

    RODATA
.include "metrics_table.inc"

.set LS_LABEL1, 0                       /* the first label table's record, or 0 */
.set LS_LABEL2, 8                       /* the second's, or 0 */
.set LS_I1, 16                          /* the value index in the first */
.set LS_I2, 24                          /* the value index in the second */

/* The x1 bytes at x0 go to the cursor. Uses x0, x1, x9, x10. */
LOCAL_FUNCTION lantern_mt_put
    UNWIND_END_PROLOGUE
    cbnz    x22, 9f
    add     x9, x20, x1
    cmp     x9, x21
    b.hi    8f
    cbz     x1, 9f
1:  ldrb    w10, [x0], #1
    strb    w10, [x20], #1
    subs    x1, x1, #1
    b.ne    1b
    ret
8:  mov     x22, #1
9:  ret
END_FUNCTION lantern_mt_put

/* The text at metrics_texts + x0, of x1 bytes. Uses x0, x1, x9, x10. */
LOCAL_FUNCTION lantern_mt_text
    UNWIND_END_PROLOGUE
    add     x0, x19, x0
    b       lantern_mt_put
END_FUNCTION lantern_mt_text

.macro MT_TEXT label
    ADDRESS x0, \label
    mov     x1, #\label\()_len
    bl      lantern_mt_put
.endm

/* The decimal digits of x0. Locals: the digits, from the end. Uses x0, x1, x9-x15. */
LOCAL_FUNCTION lantern_mt_dec
    FRAME 32
    add     x11, sp, #48
    mov     x12, x11
    mov     x13, #10
1:  udiv    x14, x0, x13
    msub    x15, x14, x13, x0
    add     w15, w15, #0x30
    strb    w15, [x12, #-1]!
    mov     x0, x14
    cbnz    x0, 1b
    mov     x0, x12
    sub     x1, x11, x12
    bl      lantern_mt_put
    UNFRAME 32
END_FUNCTION lantern_mt_dec

/* x0 as a signed decimal. Locals: x0, the sign. */
LOCAL_FUNCTION lantern_mt_sdec
    FRAME 16
    str     x0, [sp, #16]
    tbz     x0, #63, 1f
    mov     w9, #0x2d                       /* "-", then the digits of 0 - x0 (2^63 stays 2^63, unsigned) */
    strb    w9, [sp, #24]
    add     x0, sp, #24
    mov     x1, #1
    bl      lantern_mt_put
    ldr     x0, [sp, #16]
    neg     x0, x0
    str     x0, [sp, #16]
1:  ldr     x0, [sp, #16]
    bl      lantern_mt_dec
    UNFRAME 16
END_FUNCTION lantern_mt_sdec

/* The microseconds x0 as seconds: the whole seconds, ".", six digits. Locals: the rest, the digits. */
LOCAL_FUNCTION lantern_mt_seconds
    FRAME 32
    MOVQ    x9, 1000000
    udiv    x10, x0, x9
    msub    x11, x10, x9, x0
    str     x11, [sp, #16]
    mov     x0, x10
    bl      lantern_mt_dec
    mov     w9, #0x2e                       /* "." */
    strb    w9, [sp, #24]
    ldr     x0, [sp, #16]                   /* six digits, from the end */
    mov     x13, #10
    add     x12, sp, #31
    mov     x11, #6
1:  udiv    x14, x0, x13
    msub    x15, x14, x13, x0
    add     w15, w15, #0x30
    strb    w15, [x12, #-1]!
    mov     x0, x14
    subs    x11, x11, #1
    b.ne    1b
    add     x0, sp, #24
    mov     x1, #7
    bl      lantern_mt_put
    UNFRAME 32
END_FUNCTION lantern_mt_seconds

/*
 * The ticks x0 as microseconds: x0 * 10^6 / x1 by long division of the 128-bit product, or the
 * largest u64 when the quotient does not fit; 0 when x1 is 0. Uses x0, x9-x14.
 */
LOCAL_FUNCTION lantern_mt_ticks_us
    UNWIND_END_PROLOGUE
    cbz     x1, 8f
    MOVQ    x9, 1000000
    umulh   x10, x0, x9                     /* the product: x10 high, x11 low */
    mul     x11, x0, x9
    cmp     x10, x1
    b.hs    9f
    mov     x0, #0
    mov     x12, #64
1:  lsr     x13, x10, #63                   /* the remainder and the low bits one place up */
    extr    x10, x10, x11, #63
    lsl     x11, x11, #1
    lsl     x0, x0, #1
    cmp     x10, x1
    cset    x14, hs
    orr     x14, x14, x13
    cbz     x14, 2f
    sub     x10, x10, x1
    orr     x0, x0, #1
2:  subs    x12, x12, #1
    b.ne    1b
    ret
8:  mov     x0, #0
    ret
9:  mov     x0, #-1
    ret
END_FUNCTION lantern_mt_ticks_us

/* The entry x23's name. Uses x0, x1, x9, x10. */
LOCAL_FUNCTION lantern_mt_name
    UNWIND_END_PROLOGUE
    ldr     w0, [x23, #MetricEntry_name]
    ldr     w1, [x23, #MetricEntry_name_len]
    b       lantern_mt_text
END_FUNCTION lantern_mt_name

/*
 * lantern_metrics_observe(histogram, bounds, value) -> status
 * The value joins the Histogram of the bound set bounds (METRIC_BOUNDS_*, of microseconds): count,
 * sum, and the bucket of the first bound at or above it, else the last. A leaf.
 */
LEAF lantern_metrics_observe
    ldr     x1, [x1]
    ldr     x2, [x2]
    ldp     x9, x10, [x0]                   /* count, sum */
    add     x9, x9, #1
    add     x10, x10, x2
    stp     x9, x10, [x0]
    ADDRESS x9, metrics_bounds
    add     x9, x9, x1, lsl #4
    ldr     w10, [x9, #MetricBounds_count]
    ldr     w11, [x9, #MetricBounds_first]
    ADDRESS x12, metrics_bound_values
    add     x12, x12, x11, lsl #4
    mov     x13, #0
1:  cmp     x13, x10
    b.hs    2f
    ldr     x14, [x12, #MetricBound_value]
    cmp     x2, x14
    b.ls    2f
    add     x12, x12, #MetricBound__mem
    add     x13, x13, #1
    b       1b
2:  add     x9, x0, #Histogram_buckets
    ldr     x10, [x9, x13, lsl #3]
    add     x10, x10, #1
    str     x10, [x9, x13, lsl #3]
    mov     x0, #LANTERN_OK
    ret
END_FUNCTION lantern_metrics_observe

/* `name="value"` of the label table record x0 and value index x1. Locals: x0, x1. */
LOCAL_FUNCTION lantern_mt_label
    FRAME 16
    stp     x0, x1, [sp, #16]
    ldr     w1, [x0, #MetricLabel_name_len]
    ldr     w0, [x0, #MetricLabel_name]
    bl      lantern_mt_text
    MT_TEXT mx_eq
    ldp     x9, x10, [sp, #16]              /* the value: metrics_label_values[first + index] */
    ldr     w11, [x9, #MetricLabel_first]
    add     x11, x11, x10
    ADDRESS x12, metrics_label_values
    add     x12, x12, x11, lsl #3
    ldp     w0, w1, [x12]
    bl      lantern_mt_text
    MT_TEXT mx_quote
    UNFRAME 16
END_FUNCTION lantern_mt_label

/*
 * A sample's start: the entry x23's name, the suffix of x1 bytes at x0 (none when x1 is 0), then "{"
 * and the labels of the LabelState x2 when it has a label. x0 = 1 when a "{" went out, else 0.
 * Locals: the LabelState, the flag, the suffix, its length.
 */
LOCAL_FUNCTION lantern_mt_open
    FRAME 32
    stp     x2, xzr, [sp, #16]
    stp     x0, x1, [sp, #32]
    bl      lantern_mt_name
    ldp     x0, x1, [sp, #32]
    cbz     x1, 1f
    bl      lantern_mt_put
1:  ldr     x9, [sp, #16]
    ldr     x10, [x9, #LS_LABEL1]
    cbz     x10, 9f
    mov     x10, #1
    str     x10, [sp, #24]
    MT_TEXT mx_lbrace
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #LS_LABEL1]
    ldr     x1, [x9, #LS_I1]
    bl      lantern_mt_label
    ldr     x9, [sp, #16]
    ldr     x10, [x9, #LS_LABEL2]
    cbz     x10, 9f
    MT_TEXT mx_comma
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #LS_LABEL2]
    ldr     x1, [x9, #LS_I2]
    bl      lantern_mt_label
9:  ldr     x0, [sp, #24]
    UNFRAME 32
END_FUNCTION lantern_mt_open

/* A sample's end: "}" when x0 is 1, " ", then the decimal x1 and LF. Locals: x1. */
LOCAL_FUNCTION lantern_mt_value
    FRAME 16
    str     x1, [sp, #16]
    cbz     x0, 1f
    MT_TEXT mx_rbrace
1:  MT_TEXT mx_sp
    ldr     x0, [sp, #16]
    bl      lantern_mt_dec
    MT_TEXT mx_lf
    UNFRAME 16
END_FUNCTION lantern_mt_value

/* `{` when x0 is 0, else `,`; then `le="`. */
LOCAL_FUNCTION lantern_mt_le
    FRAME 0
    cbnz    x0, 1f
    MT_TEXT mx_lbrace
    b       2f
1:  MT_TEXT mx_comma
2:  MT_TEXT mx_le
    MT_TEXT mx_eq
    UNFRAME 0
END_FUNCTION lantern_mt_le

/*
 * The histogram x0 of the bound set record x1, with the labels of the LabelState x2; x3 is the
 * ticks per second for a set of ticks. Locals: the Histogram, the bounds, the LabelState, the tick
 * rate, the bound index, the sum so far.
 */
LOCAL_FUNCTION lantern_mt_histogram
    FRAME 48
    stp     x0, x1, [sp, #16]
    stp     x2, x3, [sp, #32]
    stp     xzr, xzr, [sp, #48]
1:  ldp     x9, x10, [sp, #48]              /* each bound: the values at or below it */
    ldr     x11, [sp, #24]
    ldr     w12, [x11, #MetricBounds_count]
    cmp     x9, x12
    b.hs    2f
    ldr     x13, [sp, #16]
    add     x13, x13, #Histogram_buckets
    ldr     x13, [x13, x9, lsl #3]
    add     x10, x10, x13
    str     x10, [sp, #56]
    ADDRESS x0, mx_bucket
    mov     x1, #mx_bucket_len
    ldr     x2, [sp, #32]
    bl      lantern_mt_open
    bl      lantern_mt_le
    ldr     x9, [sp, #48]                   /* the bound's text */
    ldr     x11, [sp, #24]
    ldr     w12, [x11, #MetricBounds_first]
    add     x12, x12, x9
    ADDRESS x13, metrics_bound_values
    add     x13, x13, x12, lsl #4
    ldr     w0, [x13, #MetricBound_text]
    ldr     w1, [x13, #MetricBound_text_len]
    bl      lantern_mt_text
    MT_TEXT mx_quote
    mov     x0, #1
    ldr     x1, [sp, #56]
    bl      lantern_mt_value
    ldr     x9, [sp, #48]
    add     x9, x9, #1
    str     x9, [sp, #48]
    b       1b
    /* +Inf: every value */
2:  ADDRESS x0, mx_bucket
    mov     x1, #mx_bucket_len
    ldr     x2, [sp, #32]
    bl      lantern_mt_open
    bl      lantern_mt_le
    MT_TEXT mx_inf
    MT_TEXT mx_quote
    mov     x0, #1
    ldr     x9, [sp, #16]
    ldr     x1, [x9, #Histogram_count]
    bl      lantern_mt_value
    /* _sum in seconds */
    ADDRESS x0, mx_sum
    mov     x1, #mx_sum_len
    ldr     x2, [sp, #32]
    bl      lantern_mt_open
    cbz     x0, 3f
    MT_TEXT mx_rbrace
3:  MT_TEXT mx_sp
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #Histogram_sum]
    ldr     x11, [sp, #24]
    ldr     w12, [x11, #MetricBounds_unit]
    cmp     w12, #METRIC_UNIT_TICKS
    b.ne    4f
    ldr     x1, [sp, #40]                   /* ticks: sum * 10^6 / the rate, in microseconds */
    bl      lantern_mt_ticks_us
4:  bl      lantern_mt_seconds
    MT_TEXT mx_lf
    /* _count */
    ADDRESS x0, mx_count
    mov     x1, #mx_count_len
    ldr     x2, [sp, #32]
    bl      lantern_mt_open
    ldr     x9, [sp, #16]
    ldr     x1, [x9, #Histogram_count]
    bl      lantern_mt_value
    UNFRAME 48
END_FUNCTION lantern_mt_histogram

/* The entry x23's name and `{topic="<name>"` of the GossipTopic x0. Locals: the topic. */
LOCAL_FUNCTION lantern_mt_topic
    FRAME 16
    str     x0, [sp, #16]
    bl      lantern_mt_name
    MT_TEXT mx_lbrace
    MT_TEXT mx_topic
    MT_TEXT mx_eq
    ldr     x9, [sp, #16]
    add     x0, x9, #GossipTopic_name
    ldr     x1, [x9, #GossipTopic_name_length]
    bl      lantern_mt_put
    MT_TEXT mx_quote
    UNFRAME 16
END_FUNCTION lantern_mt_topic

/* `,<name>="<value>"`: the name is x1 bytes at x0, the value x3 bytes at x2. Locals: the texts. */
LOCAL_FUNCTION lantern_mt_pair
    FRAME 32
    stp     x0, x1, [sp, #16]
    stp     x2, x3, [sp, #32]
    MT_TEXT mx_comma
    ldp     x0, x1, [sp, #16]
    bl      lantern_mt_put
    MT_TEXT mx_eq
    ldp     x0, x1, [sp, #32]
    bl      lantern_mt_put
    MT_TEXT mx_quote
    UNFRAME 32
END_FUNCTION lantern_mt_pair

.macro MT_PAIR name, value
    ADDRESS x0, \name
    mov     x1, #\name\()_len
    ADDRESS x2, \value
    mov     x3, #\value\()_len
    bl      lantern_mt_pair
.endm

/* The element x28's label value indices into the LabelState: x28 / the second label's count, x28 % it. */
.macro MT_INDICES
    ldr     x9, [sp, #(L + 72)]
    udiv    x10, x28, x9
    msub    x11, x10, x9, x28
    add     x12, sp, #(L + 32)
    stp     x10, x11, [x12, #LS_I1]
.endm

/*
 * lantern_metrics_text(categories, state, node, counters, app, process, gossip, profile, out) -> status
 * The Prometheus text of the metrics of the categories. x19 metrics_texts, x20 the cursor, x21 the
 * end of the room, x22 1 when the room ran out, x23 a table entry, x24 the entry's value, x25 its
 * kind, x26 a gossip topic, x27 the gossip topics left, x28 the element. Locals: L the categories,
 * L+8 the sources' table, L+16 out, L+24 the ticks per second, L+32 a LabelState (32 bytes), L+64 the
 * elements, L+72 the second label's value count, L+80 the sources' table: MetricsSources (56 bytes).
 */
FUNCTION lantern_metrics_text
    ENTER 144
    stp     x1, x2, [sp, #(L + 80 + MetricsSources_state)]     /* the sources, in a table of its own */
    stp     x3, x4, [sp, #(L + 80 + MetricsSources_counters)]
    stp     x5, x6, [sp, #(L + 80 + MetricsSources_process)]
    str     x7, [sp, #(L + 80 + MetricsSources_profile)]
    ldr     x2, [sp, #(96 + 144)]           /* the ninth argument: out */
    add     x1, sp, #(L + 80)
    ldr     x0, [x0]
    stp     x0, x1, [sp, #L]
    str     x2, [sp, #(L + 16)]
    add     x20, x2, #24
    ldr     x21, [x2]
    add     x21, x21, x2
    mov     x22, #0
    ADDRESS x19, metrics_texts
    ldr     x9, [x1, #MetricsSources_profile]
    cbz     x9, 1f
    ldr     x9, [x9, #Profile_ticks_per_second]
1:  str     x9, [sp, #(L + 24)]
    ADDRESS x23, metrics_table
10: ADDRESS x9, metrics_table_end
    cmp     x23, x9
    b.hs    90f
    ldr     w9, [x23, #MetricEntry_bit]     /* its category */
    ldr     x10, [sp, #L]
    lsr     x10, x10, x9
    tbz     x10, #0, 80f
    ldr     w9, [x23, #MetricEntry_source]  /* its source, given */
    ldr     x10, [sp, #(L + 8)]
    ldr     x24, [x10, x9, lsl #3]
    cbz     x24, 80f
    ldrh    w9, [x23, #MetricEntry_cond]    /* its condition */
    ldr     x11, [x10, #MetricsSources_state]
    cmp     w9, #METRIC_COND_NONE
    b.eq    20f
    cmp     w9, #METRIC_COND_STATE
    b.eq    11f
    cmp     w9, #METRIC_COND_ELECTRA
    b.eq    12f
    cmp     w9, #METRIC_COND_STATE_ROOT
    b.eq    13f
    cmp     w9, #METRIC_COND_FULU
    b.eq    14f
    cmp     w9, #METRIC_COND_MAX_FDS
    b.eq    15f
    cmp     w9, #METRIC_COND_ALTAIR
    b.eq    16f
    ldr     x12, [sp, #(L + 24)]            /* METRIC_COND_PROFILE: a tick rate */
    cbz     x12, 80f
    b       20f
11: cbz     x11, 80f
    ldr     x12, [x11, #MetricsState_present]
    cbz     x12, 80f
    b       20f
12: cbz     x11, 80f
    ldr     x12, [x11, #MetricsState_present]
    cbz     x12, 80f
    ldr     x12, [x11, #MetricsState_electra]
    cbz     x12, 80f
    b       20f
16: cbz     x11, 80f
    ldr     x12, [x11, #MetricsState_present]
    cbz     x12, 80f
    ldr     x12, [x11, #MetricsState_altair]
    cbz     x12, 80f
    b       20f
13: cbz     x11, 80f
    ldr     x12, [x11, #MetricsState_present]
    cbz     x12, 80f
    ldr     x12, [x11, #MetricsState_state_root_present]
    cbz     x12, 80f
    b       20f
14: ldr     x11, [x10, #MetricsSources_node]
    cbz     x11, 80f
    ldr     x12, [x11, #MetricsNode_fulu]
    cbz     x12, 80f
    b       20f
15: ldr     x11, [x10, #MetricsSources_process]
    cbz     x11, 80f
    ldr     x12, [x11, #MetricsProcess_max_fds]
    cbz     x12, 80f
20: ldrh    w25, [x23, #MetricEntry_kind]   /* a gossipsub family with no sample does not go out */
    cmp     w25, #METRIC_KIND_GOSSIP_MAIN
    b.lo    30f
    PART    x10, x11, x24, MetricsGossip_topics
21: cbz     x11, 80f
    cmp     w25, #METRIC_KIND_GOSSIP_MAIN
    b.ne    30f
    ldr     x12, [x10, #GossipTopic_subnet]
    cbz     x12, 30f
    add     x10, x10, #GossipTopic__mem
    sub     x11, x11, #1
    b       21b
    /* # HELP <name> <help>; # TYPE <name> <type> */
30: MT_TEXT mx_help
    bl      lantern_mt_name
    MT_TEXT mx_sp
    ldr     w0, [x23, #MetricEntry_help]
    ldr     w1, [x23, #MetricEntry_help_len]
    bl      lantern_mt_text
    MT_TEXT mx_lf
    MT_TEXT mx_type
    bl      lantern_mt_name
    ldr     w9, [x23, #MetricEntry_type]
    cmp     w9, #METRIC_TYPE_COUNTER
    b.eq    31f
    b.hi    32f
    MT_TEXT mx_gauge
    b       33f
31: MT_TEXT mx_counter
    b       33f
32: MT_TEXT mx_histogram
33: ldr     w9, [x23, #MetricEntry_offset]  /* its value in its source; its label tables */
    add     x24, x24, x9
    add     x9, sp, #(L + 32)
    stp     xzr, xzr, [x9]
    stp     xzr, xzr, [x9, #16]
    mov     x28, #0
    mov     x10, #1
    str     x10, [sp, #(L + 72)]
    ADDRESS x11, metrics_labels
    ldrh    w10, [x23, #MetricEntry_label1]
    cbz     w10, 34f
    sub     w10, w10, #1
    add     x10, x11, x10, lsl #4
    str     x10, [x9, #LS_LABEL1]
    ldrh    w10, [x23, #MetricEntry_label2]
    cbz     w10, 34f
    sub     w10, w10, #1
    add     x10, x11, x10, lsl #4
    str     x10, [x9, #LS_LABEL2]
    ldr     w10, [x10, #MetricLabel_count]
    str     x10, [sp, #(L + 72)]
34: ldr     w10, [x23, #MetricEntry_count]
    str     x10, [sp, #(L + 64)]
    cmp     w25, #METRIC_KIND_U64
    b.eq    40f
    cmp     w25, #METRIC_KIND_ROOT
    b.eq    41f
    cmp     w25, #METRIC_KIND_SECONDS
    b.eq    42f
    cmp     w25, #METRIC_KIND_ARRAY
    b.eq    43f
    cmp     w25, #METRIC_KIND_HIST
    b.eq    44f
    cmp     w25, #METRIC_KIND_ARRAY_HIST
    b.eq    44f
    b       50f
40: mov     x0, #0                          /* a value */
    mov     x1, #0
    add     x2, sp, #(L + 32)
    bl      lantern_mt_open
    ldr     x1, [x24]
    bl      lantern_mt_value
    b       80f
41: bl      lantern_mt_name                         /* a root, signed */
    MT_TEXT mx_sp
    ldr     x0, [x24]
    bl      lantern_mt_sdec
    MT_TEXT mx_lf
    b       80f
42: bl      lantern_mt_name                         /* microseconds as seconds */
    MT_TEXT mx_sp
    ldr     x0, [x24]
    bl      lantern_mt_seconds
    MT_TEXT mx_lf
    b       80f
43: ldr     x9, [sp, #(L + 64)]             /* values by labels: element e at e * 8 */
    cmp     x28, x9
    b.hs    80f
    MT_INDICES
    mov     x0, #0
    mov     x1, #0
    add     x2, sp, #(L + 32)
    bl      lantern_mt_open
    ldr     x1, [x24, x28, lsl #3]
    bl      lantern_mt_value
    add     x28, x28, #1
    b       43b
44: ldr     x9, [sp, #(L + 64)]             /* histograms by labels: element e at e * Histogram__mem */
    cmp     x28, x9
    b.hs    80f
    MT_INDICES
    mov     x9, #Histogram__mem
    madd    x0, x28, x9, x24
    ldrh    w9, [x23, #MetricEntry_bounds]
    ADDRESS x1, metrics_bounds
    add     x1, x1, x9, lsl #4
    add     x2, sp, #(L + 32)
    ldr     x3, [sp, #(L + 24)]
    bl      lantern_mt_histogram
    add     x28, x28, #1
    b       44b
    /* gossipsub: each topic */
50: PART    x26, x27, x24, MetricsGossip_topics
51: cbz     x27, 80f
    cmp     w25, #METRIC_KIND_GOSSIP_MAIN
    b.ne    52f
    ldr     x9, [x26, #GossipTopic_subnet]  /* main topics only */
    cbnz    x9, 59f
    mov     x0, x26
    bl      lantern_mt_topic
    mov     x0, #1
    ldr     x1, [x26, #GossipTopic_mesh_peers]
    bl      lantern_mt_value
    b       59f
52: cmp     w25, #METRIC_KIND_GOSSIP_SENT
    b.ne    53f
    mov     x0, x26
    bl      lantern_mt_topic
    MT_PAIR mx_partial, mx_false
    mov     x0, #1
    ldr     x1, [x26, #GossipTopic_sent_bytes]
    bl      lantern_mt_value
    mov     x0, x26
    bl      lantern_mt_topic
    MT_PAIR mx_partial, mx_true
    mov     x0, #1
    ldr     x1, [x26, #GossipTopic_sent_partial_bytes]
    bl      lantern_mt_value
    b       59f
53: mov     x0, x26                         /* mesh peers by partial support */
    bl      lantern_mt_topic
    MT_PAIR mx_supports, mx_false
    mov     x0, #1
    ldr     x1, [x26, #GossipTopic_mesh_peers]
    ldr     x9, [x26, #GossipTopic_mesh_partial_peers]
    sub     x1, x1, x9
    bl      lantern_mt_value
    mov     x0, x26
    bl      lantern_mt_topic
    MT_PAIR mx_supports, mx_true
    mov     x0, #1
    ldr     x1, [x26, #GossipTopic_mesh_partial_peers]
    bl      lantern_mt_value
59: add     x26, x26, #GossipTopic__mem
    sub     x27, x27, #1
    b       51b
80: add     x23, x23, #MetricEntry__mem
    b       10b
90: cbnz    x22, 91f                        /* the text's length, or no room */
    ldr     x9, [sp, #(L + 16)]
    mov     x10, #24
    str     x10, [x9, #8]
    add     x10, x9, #24
    sub     x10, x20, x10
    str     x10, [x9, #16]
    mov     x0, #LANTERN_OK
    LEAVE 144
91: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 144
END_FUNCTION lantern_metrics_text

.set MN_CHAIN, 2 * SLOTS_PER_EPOCH         /* the head's chain from the previous epoch on: at most two epochs of blocks */

/*
 * lantern_metrics_node(node, store, out) -> status
 * The node's and store's values of the metrics. x19 node, x20 store, x21 out, x22 the store's slot,
 * x23 the head's NodeBlock or 0, x24 the head's chain blocks, x25 the store's epoch, x26 the
 * previous epoch's first slot. Below the frame, from sp: their NodeBlock addresses (MN_CHAIN).
 */
FUNCTION lantern_metrics_node
    ENTER_OUT 0, (8 * MN_CHAIN)
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x9, #0                          /* out: zero */
1:  str     xzr, [x21, x9]
    add     x9, x9, #8
    cmp     x9, #MetricsNode__mem
    b.lo    1b
    LDQ     x9, x19, Node_peers + 8
    str     x9, [x21, #MetricsNode_peers]
    mov     x0, x20
    bl      lantern_node_store_slot
    mov     x22, x0
    mov     x9, #SLOTS_PER_EPOCH            /* the store's epoch: from fulu, the custody groups */
    udiv    x25, x22, x9
    LDQ     x9, x19, Node_config + CONFIG_FULU_FORK_EPOCH
    cmp     x25, x9
    b.lo    2f
    mov     x9, #1
    str     x9, [x21, #MetricsNode_fulu]
    LDQ     x9, x19, Node_custody_count
    str     x9, [x21, #MetricsNode_custody_groups]
    /* the pool's voluntary exits */
2:  PART    x9, x10, x19, Node_pool
    mov     x11, #0
3:  cbz     x10, 4f
    ldr     x12, [x9, #NodePool_topic]
    cmp     x12, #GOSSIP_VOLUNTARY_EXIT
    cinc    x11, x11, eq
    sub     x13, x12, #1                    /* and the pool's entries by topic */
    cmp     x13, #(GOSSIP_NAMES - 1)
    b.hi    31f
    add     x13, x21, #MetricsNode_pool
    ldr     x14, [x13, x12, lsl #3]
    add     x14, x14, #1
    str     x14, [x13, x12, lsl #3]
31: add     x9, x9, #NodePool__mem
    sub     x10, x10, #1
    b       3b
4:  str     x11, [x21, #MetricsNode_pending_exits]
    /* the proposers that hold: until_epoch above the store's epoch */
    PART    x9, x10, x19, Node_proposers
    mov     x11, #0
5:  cbz     x10, 6f
    ldr     x12, [x9, #NodeProposer_until_epoch]
    cmp     x12, x25
    cinc    x11, x11, hi
    add     x9, x9, #NodeProposer__mem
    sub     x10, x10, #1
    b       5b
6:  str     x11, [x21, #MetricsNode_local_validators]
    /* the head's block: its buffers and slot */
    ADDQ    x0, x19, Node_head_root
    bl      lantern_node_find_block
    mov     x23, #0
    mov     x9, #0
    cmn     x0, #1
    b.eq    7f
    mov     x23, x1
    ldr     x10, [x23, #NodeBlock_data_id]
    str     x10, [x21, #MetricsNode_head_block_id]
    ldr     x10, [x23, #NodeBlock_state_id]
    str     x10, [x21, #MetricsNode_head_state_id]
    ldr     x9, [x23, #NodeBlock_slot]
    /* synced: the head at most a slot behind; else syncing with a request open */
7:  add     x9, x9, #1
    mov     x10, #1
    cmp     x9, x22
    b.hs    8f
    mov     x10, #2                         /* else syncing with a request open */
    LDQ     x11, x19, Node_flags
    tst     x11, #NODE_FLAG_SYNCING
    b.ne    8f
    /* else synced when a peer of the node's ForkDigest has a Status and none has a head above the head's slot + 1 */
    mov     x10, #0
    PART    x11, x12, x19, Node_peers
    ldr     w13, [x19, #Node_fork_digest]
71: cbz     x12, 8f
    ldr     x14, [x11, #NodePeer_flags]
    tbz     x14, #0, 72f                    /* NODE_PEER_STATUS */
    ldr     w14, [x11, #NodePeer_fork_digest]
    cmp     w14, w13
    b.ne    72f
    ldr     x14, [x11, #NodePeer_head_slot]
    cmp     x14, x9
    b.hi    73f
    mov     x10, #1
72: add     x11, x11, #NodePeer__mem
    sub     x12, x12, #1
    b       71b
73: mov     x10, #0                         /* a peer ahead: behind */
8:  str     x10, [x21, #MetricsNode_sync_state]
    str     x22, [x21, #MetricsNode_store_slot]  /* the sync: the head's slot and its distance to the store's */
    mov     x9, #0
    cbz     x23, 81f
    ldr     x9, [x23, #NodeBlock_slot]
81: str     x9, [x21, #MetricsNode_head_slot]
    subs    x10, x22, x9
    csel    x10, xzr, x10, lo
    str     x10, [x21, #MetricsNode_distance]
    LDQ     x9, x19, Node_dialing
    str     x9, [x21, #MetricsNode_dialing]
    LDQ     x9, x19, Node_earliest_slot
    str     x9, [x21, #MetricsNode_earliest_slot]
    LDQ     x9, x19, Node_backfill_slot
    str     x9, [x21, #MetricsNode_backfill_slot]
    ldr     x9, [x20, #Store_finalized_checkpoint]
    str     x9, [x21, #MetricsNode_finalized_epoch]
    ldr     x9, [x20, #Store_justified_checkpoint]
    str     x9, [x21, #MetricsNode_justified_epoch]
    LDQ     x9, x19, Node_messages + 8
    str     x9, [x21, #MetricsNode_messages]
    LDQ     x9, x19, Node_streams + 8
    str     x9, [x21, #MetricsNode_streams]
    PART    x9, x10, x19, Node_peers
    add     x13, x21, #MetricsNode_peer_directions
82: cbz     x10, 83f
    ldr     x11, [x9, #NodePeer_direction]
    and     x11, x11, #1
    ldr     x12, [x13, x11, lsl #3]
    add     x12, x12, #1
    str     x12, [x13, x11, lsl #3]
    add     x9, x9, #NodePeer__mem
    sub     x10, x10, #1
    b       82b
83:
    subs    x26, x25, #1                    /* the previous epoch's first slot */
    csel    x26, xzr, x26, lo
    mov     x9, #SLOTS_PER_EPOCH
    mul     x26, x26, x9
    mov     x24, #0                         /* the head's chain from it on, by parent_root, to a gap */
    mov     x1, x23
9:  cbz     x1, 12f
    cmp     x24, #MN_CHAIN
    b.hs    12f
    ldr     x9, [x1, #NodeBlock_slot]
    cmp     x9, x26
    b.lo    12f
    mov     x9, sp
    str     x1, [x9, x24, lsl #3]
    add     x24, x24, #1
    add     x0, x1, #NodeBlock_parent_root
    bl      lantern_node_find_block
    cmn     x0, #1
    b.ne    9b
    mov     x1, #0
    b       9b
    /* the imported blocks of the previous epoch off that chain */
12: PART    x9, x10, x19, Node_blocks
    mov     x11, #0
    add     x12, x26, #SLOTS_PER_EPOCH
    mov     x15, sp
13: cbz     x10, 16f
    ldr     x13, [x9, #NodeBlock_status]
    cmp     x13, #NODE_BLOCK_IMPORTED
    b.ne    15f
    ldr     x13, [x9, #NodeBlock_slot]
    cmp     x13, x26
    b.lo    15f
    cmp     x13, x12
    b.hs    15f
    mov     x13, #0
14: cmp     x13, x24
    b.hs    141f
    ldr     x14, [x15, x13, lsl #3]
    cmp     x14, x9
    b.eq    15f
    add     x13, x13, #1
    b       14b
141: add    x11, x11, #1
15: add     x9, x9, #NodeBlock__mem
    sub     x10, x10, #1
    b       13b
16: str     x11, [x21, #MetricsNode_orphaned_blocks]
    mov     x0, #LANTERN_OK
    LEAVE_OUT 0, (8 * MN_CHAIN)
END_FUNCTION lantern_metrics_node

/*
 * lantern_metrics_answer(bytes, categories, state, node, counters, app, process, gossip, profile, out) -> status
 * The answer to the first request of a metrics connection's bytes. x19 metrics_texts, x20 the
 * cursor, x21 the end of the room, x22 1 when the room ran out, x23 out, x24 the status. Locals: L
 * bytes, L+8 categories, L+24 HttpLimits, L+48 the sources (as MetricsSources, 56 bytes).
 */
FUNCTION lantern_metrics_answer
    ENTER 112
    stp     x0, x1, [sp, #L]
    stp     x2, x3, [sp, #(L + 48 + MetricsSources_state)]     /* the sources */
    stp     x4, x5, [sp, #(L + 48 + MetricsSources_counters)]
    stp     x6, x7, [sp, #(L + 48 + MetricsSources_process)]
    ldp     x9, x23, [sp, #(96 + 112)]      /* the ninth and tenth arguments: profile, out */
    str     x9, [sp, #(L + 48 + MetricsSources_profile)]
    ADDRESS x19, metrics_texts
    ldr     x9, [x0, #16]                   /* room: the HttpRequest of the bytes, and the head */
    add     x9, x9, #(24 + HTTP_REQUEST_FIXED + 64 + METRICS_HEAD_ROOM)
    ldr     x10, [x23]
    cmp     x9, x10
    b.hi    98f
    sub     x10, x10, #24                   /* the request, in out's room */
    str     x10, [x23, #24]
    mov     x9, #METRICS_HEAD_MAX
    stp     x9, xzr, [sp, #(L + 24)]
    add     x1, sp, #(L + 24)
    add     x2, x23, #24
    CALL_GLOBAL lantern_http_request
    cmp     x0, #LANTERN_HTTP_MORE
    b.eq    97f
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    98f
    ldr     x24, [x23, #(24 + HttpRequest_status)]
    cbnz    x0, 50f
    mov     x24, #405
    ldr     x9, [x23, #(24 + HttpRequest_method)]
    cmp     x9, #HTTP_METHOD_GET
    b.ne    50f
    mov     x24, #404                       /* the path: /metrics */
    add     x9, x23, #24
    PART    x10, x11, x9, HttpRequest_path
    cmp     x11, #mx_path_len
    b.ne    50f
    ldr     x10, [x10]
    ADDRESS x9, mx_path
    ldr     x9, [x9]
    cmp     x10, x9
    b.ne    50f
    ldr     x9, [x23]                       /* 200: the text after METRICS_HEAD_ROOM bytes */
    sub     x9, x9, #METRICS_HEAD_ROOM
    str     x9, [x23, #METRICS_HEAD_ROOM]
    ldr     x0, [sp, #(L + 8)]
    ldp     x1, x2, [sp, #(L + 48 + MetricsSources_state)]
    ldp     x3, x4, [sp, #(L + 48 + MetricsSources_counters)]
    ldp     x5, x6, [sp, #(L + 48 + MetricsSources_process)]
    ldr     x7, [sp, #(L + 48 + MetricsSources_profile)]
    add     x9, x23, #METRICS_HEAD_ROOM
    sub     sp, sp, #16                     /* the ninth argument: out */
    str     x9, [sp]
    bl      lantern_metrics_text
    add     sp, sp, #16
    cbnz    x0, 98f
    /* the head before it; then the text moves up to the head */
    add     x20, x23, #24
    add     x21, x23, #METRICS_HEAD_ROOM
    mov     x22, #0
    MT_TEXT mx_http
    MT_TEXT mx_ok_head
    ldr     x0, [x23, #(METRICS_HEAD_ROOM + 16)]
    bl      lantern_mt_dec
    MT_TEXT mx_close
    mov     x0, x20
    add     x1, x23, #(METRICS_HEAD_ROOM + 24)
    ldr     x2, [x23, #(METRICS_HEAD_ROOM + 16)]
    add     x20, x20, x2
    bl      lantern_copy
    b       90f
    /* HTTP/1.1 <status> <reason>; Allow: GET for 405; no body */
50: add     x20, x23, #24
    add     x21, x23, #METRICS_HEAD_ROOM
    mov     x22, #0
    MT_TEXT mx_http
    mov     x0, x24
    bl      lantern_mt_dec
    MT_TEXT mx_sp
    mov     x0, x24
    bl      lantern_api_code
    cbz     x0, 51f
    ldp     x9, x1, [x0, #8]
    ADDRESS x0, api_texts
    add     x0, x0, x9
    bl      lantern_mt_put
51: MT_TEXT mx_crlf
    cmp     x24, #405
    b.ne    52f
    MT_TEXT mx_allow
52: MT_TEXT mx_len0
90: mov     x9, #24                         /* out: the answer's bytes */
    str     x9, [x23, #8]
    add     x9, x23, #24
    sub     x9, x20, x9
    str     x9, [x23, #16]
    mov     x0, #LANTERN_OK
    LEAVE 112
97: mov     x0, #LANTERN_HTTP_MORE
    LEAVE 112
98: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 112
END_FUNCTION lantern_metrics_answer
