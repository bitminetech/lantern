/*
 * Metrics, ARM64: in the common object. Requirements: docs/reference/metrics.md.
 *
 * The writers keep the cursor in x20 and the end of the room in x21; x22 becomes 1 when the room
 * runs out, and nothing is written from then on. x19 holds metrics_texts.
 */

    RODATA
.include "metrics_table.inc"

/* The x1 bytes at x0 go to the cursor. Uses x0, x1, x9, x10. */
LOCAL_FUNCTION mt_put
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
END_FUNCTION mt_put

/* The text at metrics_texts + x0, of x1 bytes. Uses x0, x1, x9, x10. */
LOCAL_FUNCTION mt_text
    UNWIND_END_PROLOGUE
    add     x0, x19, x0
    b       mt_put
END_FUNCTION mt_text

.macro MT_TEXT label
    ADDRESS x0, \label
    mov     x1, #\label\()_len
    bl      mt_put
.endm

/* The decimal digits of x0. Locals: the digits, from the end. Uses x0, x1, x9-x15. */
LOCAL_FUNCTION mt_dec
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
    bl      mt_put
    UNFRAME 32
END_FUNCTION mt_dec

/* x0 as a signed decimal. Locals: x0, the sign. */
LOCAL_FUNCTION mt_sdec
    FRAME 16
    str     x0, [sp, #16]
    tbz     x0, #63, 1f
    mov     w9, #0x2d                       /* "-", then the digits of 0 - x0 (2^63 stays 2^63, unsigned) */
    strb    w9, [sp, #24]
    add     x0, sp, #24
    mov     x1, #1
    bl      mt_put
    ldr     x0, [sp, #16]
    neg     x0, x0
    str     x0, [sp, #16]
1:  ldr     x0, [sp, #16]
    bl      mt_dec
    UNFRAME 16
END_FUNCTION mt_sdec

/* The microseconds x0 as seconds: the whole seconds, ".", six digits. Locals: the rest, the digits. */
LOCAL_FUNCTION mt_seconds
    FRAME 32
    MOVQ    x9, 1000000
    udiv    x10, x0, x9
    msub    x11, x10, x9, x0
    str     x11, [sp, #16]
    mov     x0, x10
    bl      mt_dec
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
    bl      mt_put
    UNFRAME 32
END_FUNCTION mt_seconds

/* The entry x23's name. Uses x0, x1, x9, x10. */
LOCAL_FUNCTION mt_name
    UNWIND_END_PROLOGUE
    ldr     w0, [x23, #MetricEntry_name]
    ldr     w1, [x23, #MetricEntry_name_len]
    b       mt_text
END_FUNCTION mt_name

/*
 * A histogram's samples: the entry x23, its Histogram at x0 and its bounds table at x1. Locals:
 * the Histogram, the bounds, the bound index, the sum so far.
 */
LOCAL_FUNCTION mt_histogram
    FRAME 32
    stp     x0, x1, [sp, #16]
    stp     xzr, xzr, [sp, #32]
1:  ldp     x9, x10, [sp, #32]              /* each bound: the values at or below it */
    ldr     x11, [sp, #24]
    ldr     x12, [x11]
    cmp     x9, x12
    b.hs    2f
    ldr     x13, [sp, #16]
    add     x13, x13, #Histogram_buckets
    ldr     x13, [x13, x9, lsl #3]
    add     x10, x10, x13
    str     x10, [sp, #40]
    bl      mt_name
    MT_TEXT mx_bucket
    ldr     x9, [sp, #32]
    ldr     x11, [sp, #24]
    add     x11, x11, x9, lsl #4
    ldr     w0, [x11, #16]                  /* its text: offset, length */
    ldr     w1, [x11, #20]
    bl      mt_text
    MT_TEXT mx_le_end
    ldr     x0, [sp, #40]
    bl      mt_dec
    MT_TEXT mx_lf
    ldr     x9, [sp, #32]
    add     x9, x9, #1
    str     x9, [sp, #32]
    b       1b
2:  bl      mt_name                         /* +Inf: every value */
    MT_TEXT mx_bucket
    MT_TEXT mx_inf
    MT_TEXT mx_le_end
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #Histogram_count]
    bl      mt_dec
    MT_TEXT mx_lf
    bl      mt_name                         /* _sum in seconds, _count */
    MT_TEXT mx_sum
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #Histogram_sum_us]
    bl      mt_seconds
    MT_TEXT mx_lf
    bl      mt_name
    MT_TEXT mx_count
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #Histogram_count]
    bl      mt_dec
    MT_TEXT mx_lf
    UNFRAME 32
END_FUNCTION mt_histogram

/* The topic label of the GossipTopic x0: `{topic="<name>`. Locals: the entry. */
LOCAL_FUNCTION mt_topic
    FRAME 16
    str     x0, [sp, #16]
    bl      mt_name
    MT_TEXT mx_topic
    ldr     x9, [sp, #16]
    add     x0, x9, #GossipTopic_name
    ldr     x1, [x9, #GossipTopic_name_length]
    bl      mt_put
    UNFRAME 16
END_FUNCTION mt_topic

/*
 * lantern_metrics_text(categories, state, node, app, process, gossip, out) -> status
 * The Prometheus text of the metrics of the categories. x19 metrics_texts, x20 the cursor, x21 the
 * end of the room, x22 1 when the room ran out, x23 a table entry, x24 the entry's source, x25 the
 * gossip kind, x26 a gossip entry, x27 the gossip entries left. Locals: L the sources by
 * METRIC_SRC_* (state, node, app, process, gossip), L+40 out.
 */
FUNCTION lantern_metrics_text
    ENTER 48
    stp     x1, x2, [sp, #L]
    stp     x3, x4, [sp, #(L + 16)]
    stp     x5, x6, [sp, #(L + 32)]
    ldr     x0, [x0]
    add     x20, x6, #24
    ldr     x21, [x6]
    add     x21, x21, x6
    mov     x22, #0
    ADDRESS x19, metrics_texts
    tst     x0, #METRICS_BEACON
    b.eq    90f
    ADDRESS x23, metrics_table
1:  ADDRESS x9, metrics_table_end
    cmp     x23, x9
    b.hs    90f
    ldr     w9, [x23, #MetricEntry_source]  /* its source */
    add     x10, sp, #L
    ldr     x24, [x10, x9, lsl #3]
    ldrh    w9, [x23, #MetricEntry_cond]    /* its condition */
    cmp     w9, #METRIC_COND_NONE
    b.eq    10f
    ldr     x10, [sp, #L]                   /* MetricsState */
    cmp     w9, #METRIC_COND_STATE
    b.ne    2f
    ldr     x11, [x10, #MetricsState_present]
    cbz     x11, 80f
    b       10f
2:  cmp     w9, #METRIC_COND_ELECTRA
    b.ne    3f
    ldr     x11, [x10, #MetricsState_present]
    cbz     x11, 80f
    ldr     x11, [x10, #MetricsState_electra]
    cbz     x11, 80f
    b       10f
3:  ldr     x10, [sp, #(L + 8)]             /* MetricsNode */
    cmp     w9, #METRIC_COND_FULU
    b.ne    4f
    ldr     x11, [x10, #MetricsNode_fulu]
    cbz     x11, 80f
    b       10f
4:  cmp     w9, #METRIC_COND_STATE_ROOT
    b.ne    5f
    ldr     x10, [sp, #L]                   /* MetricsState */
    ldr     x11, [x10, #MetricsState_present]
    cbz     x11, 80f
    ldr     x11, [x10, #MetricsState_state_root_present]
    cbz     x11, 80f
    b       10f
5:  ldr     x10, [sp, #(L + 24)]            /* MetricsProcess: METRIC_COND_MAX_FDS */
    ldr     x11, [x10, #MetricsProcess_max_fds]
    cbz     x11, 80f
10: ldrh    w9, [x23, #MetricEntry_kind]    /* a gossipsub metric with no sample goes out */
    cmp     w9, #METRIC_KIND_GOSSIP_MAIN
    b.lo    20f
    PART    x10, x11, x24, MetricsGossip_topics
11: cbz     x11, 80f
    cmp     w9, #METRIC_KIND_GOSSIP_MAIN
    b.ne    20f
    ldr     x12, [x10, #GossipTopic_subnet]
    cbz     x12, 20f
    add     x10, x10, #GossipTopic__mem
    sub     x11, x11, #1
    b       11b
20: MT_TEXT mx_help                         /* # HELP <name> <help>, # TYPE <name> <type> */
    bl      mt_name
    MT_TEXT mx_sp
    ldr     w0, [x23, #MetricEntry_help]
    ldr     w1, [x23, #MetricEntry_help_len]
    bl      mt_text
    MT_TEXT mx_lf
    MT_TEXT mx_type
    bl      mt_name
    ldr     w9, [x23, #MetricEntry_type]
    cmp     w9, #METRIC_TYPE_COUNTER
    b.eq    22f
    b.hi    23f
    MT_TEXT mx_gauge
    b       24f
22: MT_TEXT mx_counter
    b       24f
23: MT_TEXT mx_histogram
24: ldr     w9, [x23, #MetricEntry_offset]  /* its samples */
    add     x24, x24, x9                    /* the value, in its source */
    ldrh    w9, [x23, #MetricEntry_kind]
    cmp     w9, #METRIC_KIND_U64
    b.ne    30f
    bl      mt_name
    MT_TEXT mx_sp
    ldr     x0, [x24]
    bl      mt_dec
    MT_TEXT mx_lf
    b       80f
30: cmp     w9, #METRIC_KIND_ROOT
    b.ne    31f
    bl      mt_name
    MT_TEXT mx_sp
    ldr     x0, [x24]
    bl      mt_sdec
    MT_TEXT mx_lf
    b       80f
31: cmp     w9, #METRIC_KIND_SECONDS
    b.ne    32f
    bl      mt_name
    MT_TEXT mx_sp
    ldr     x0, [x24]
    bl      mt_seconds
    MT_TEXT mx_lf
    b       80f
32: cmp     w9, #METRIC_KIND_STATUS
    b.ne    33f
    bl      mt_name
    MT_TEXT mx_st_pending
    ldr     x0, [x24]
    bl      mt_dec
    MT_TEXT mx_lf
    bl      mt_name
    MT_TEXT mx_st_active
    ldr     x0, [x24, #8]
    bl      mt_dec
    MT_TEXT mx_lf
    bl      mt_name
    MT_TEXT mx_st_exited
    ldr     x0, [x24, #16]
    bl      mt_dec
    MT_TEXT mx_lf
    bl      mt_name
    MT_TEXT mx_st_withdrawable
    ldr     x0, [x24, #24]
    bl      mt_dec
    MT_TEXT mx_lf
    b       80f
33: cmp     w9, #METRIC_KIND_HIST_DEFAULT
    b.ne    34f
    ADDRESS x1, mb_default
    b       36f
34: cmp     w9, #METRIC_KIND_HIST_KZG
    b.ne    35f
    ADDRESS x1, mb_kzg
    b       36f
35: cmp     w9, #METRIC_KIND_HIST_DELAY
    b.ne    40f
    ADDRESS x1, mb_delay
36: mov     x0, x24
    bl      mt_histogram
    b       80f
40: mov     w25, w9                         /* gossipsub: each topic */
    ldr     w9, [x23, #MetricEntry_offset]
    sub     x24, x24, x9                    /* the MetricsGossip again */
    PART    x26, x27, x24, MetricsGossip_topics
41: cbz     x27, 80f
    cmp     w25, #METRIC_KIND_GOSSIP_MAIN
    b.ne    42f
    ldr     x9, [x26, #GossipTopic_subnet]  /* main topics only */
    cbnz    x9, 49f
    mov     x0, x26
    bl      mt_topic
    MT_TEXT mx_topic_end
    ldr     x0, [x26, #GossipTopic_mesh_peers]
    bl      mt_dec
    MT_TEXT mx_lf
    b       49f
42: cmp     w25, #METRIC_KIND_GOSSIP_SENT
    b.ne    43f
    mov     x0, x26
    bl      mt_topic
    MT_TEXT mx_partial_f
    ldr     x0, [x26, #GossipTopic_sent_bytes]
    bl      mt_dec
    MT_TEXT mx_lf
    mov     x0, x26
    bl      mt_topic
    MT_TEXT mx_partial_t
    ldr     x0, [x26, #GossipTopic_sent_partial_bytes]
    bl      mt_dec
    MT_TEXT mx_lf
    b       49f
43: mov     x0, x26                         /* mesh peers by partial support */
    bl      mt_topic
    MT_TEXT mx_supports_f
    ldr     x0, [x26, #GossipTopic_mesh_peers]
    ldr     x9, [x26, #GossipTopic_mesh_partial_peers]
    sub     x0, x0, x9
    bl      mt_dec
    MT_TEXT mx_lf
    mov     x0, x26
    bl      mt_topic
    MT_TEXT mx_supports_t
    ldr     x0, [x26, #GossipTopic_mesh_partial_peers]
    bl      mt_dec
    MT_TEXT mx_lf
49: add     x26, x26, #GossipTopic__mem
    sub     x27, x27, #1
    b       41b
80: add     x23, x23, #MetricEntry__mem
    b       1b
90: cbnz    x22, 91f                        /* the text's length, or no room */
    ldr     x9, [sp, #(L + 40)]
    mov     x10, #24
    str     x10, [x9, #8]
    add     x10, x9, #24
    sub     x10, x20, x10
    str     x10, [x9, #16]
    mov     x0, #LANTERN_OK
    LEAVE 48
91: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
END_FUNCTION lantern_metrics_text
