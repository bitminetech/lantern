/*
 * Metrics, RISC-V: in the common object. Requirements: docs/reference/metrics.md.
 *
 * The writers keep the cursor in s2 and the end of the room in s3; s4 becomes 1 when the room
 * runs out, and nothing is written from then on. s1 holds metrics_texts. A LabelState (LS_*) holds
 * the label tables of a family and the element's value index in each.
 */

    RODATA
.include "metrics_table.inc"

.set LS_LABEL1, 0                       /* the first label table's record, or 0 */
.set LS_LABEL2, 8                       /* the second's, or 0 */
.set LS_I1, 16                          /* the value index in the first */
.set LS_I2, 24                          /* the value index in the second */

# The a1 bytes at a0 go to the cursor. Uses a0, a1, t0, t1.
LOCAL_FUNCTION mt_put
    UNWIND_END_PROLOGUE
    bnez    s4, 9f
    add     t0, s2, a1
    bgtu    t0, s3, 8f
    beqz    a1, 9f
1:  lbu     t1, 0(a0)
    sb      t1, 0(s2)
    addi    a0, a0, 1
    addi    s2, s2, 1
    addi    a1, a1, -1
    bnez    a1, 1b
    ret
8:  li      s4, 1
9:  ret
END_FUNCTION mt_put

# The text at metrics_texts + a0, of a1 bytes. Uses a0, a1, t0, t1.
LOCAL_FUNCTION mt_text
    UNWIND_END_PROLOGUE
    add     a0, s1, a0
    j       mt_put
END_FUNCTION mt_text

.macro MT_TEXT label
    lla     a0, \label
    li      a1, \label\()_len
    call    mt_put
.endm

# The decimal digits of a0. Locals: the digits, from the end. Uses a0, a1, t0-t5.
LOCAL_FUNCTION mt_dec
    FRAME 32
    addi    t2, sp, 32
    mv      t3, t2
    li      t4, 10
1:  remu    t5, a0, t4
    divu    a0, a0, t4
    addi    t5, t5, 0x30
    addi    t3, t3, -1
    sb      t5, 0(t3)
    bnez    a0, 1b
    mv      a0, t3
    sub     a1, t2, t3
    call    mt_put
    UNFRAME 32
END_FUNCTION mt_dec

# a0 as a signed decimal. Locals: a0, the sign.
LOCAL_FUNCTION mt_sdec
    FRAME 16
    sd      a0, 0(sp)
    bgez    a0, 1f
    li      t0, 0x2d                        # "-", then the digits of 0 - a0 (2^63 stays 2^63, unsigned)
    sb      t0, 8(sp)
    addi    a0, sp, 8
    li      a1, 1
    call    mt_put
    ld      a0, 0(sp)
    neg     a0, a0
    sd      a0, 0(sp)
1:  ld      a0, 0(sp)
    call    mt_dec
    UNFRAME 16
END_FUNCTION mt_sdec

# The microseconds a0 as seconds: the whole seconds, ".", six digits. Locals: the rest, the digits.
LOCAL_FUNCTION mt_seconds
    FRAME 32
    li      t0, 1000000
    remu    t1, a0, t0
    divu    a0, a0, t0
    sd      t1, 0(sp)
    call    mt_dec
    li      t0, 0x2e                        # "."
    sb      t0, 8(sp)
    ld      a0, 0(sp)                       # six digits, from the end
    li      t4, 10
    addi    t3, sp, 15
    li      t2, 6
1:  remu    t5, a0, t4
    divu    a0, a0, t4
    addi    t5, t5, 0x30
    addi    t3, t3, -1
    sb      t5, 0(t3)
    addi    t2, t2, -1
    bnez    t2, 1b
    addi    a0, sp, 8
    li      a1, 7
    call    mt_put
    UNFRAME 32
END_FUNCTION mt_seconds

/*
 * The ticks a0 as microseconds: a0 * 10^6 / a1 by long division of the 128-bit product, or the
 * largest u64 when the quotient does not fit; 0 when a1 is 0. Uses a0, t0-t5.
 */
LOCAL_FUNCTION mt_ticks_us
    UNWIND_END_PROLOGUE
    beqz    a1, 8f
    li      t0, 1000000
    mulhu   t1, a0, t0                      # the product: t1 high, t2 low
    mul     t2, a0, t0
    bgeu    t1, a1, 9f
    li      a0, 0
    li      t3, 64
1:  srli    t4, t1, 63                      # the remainder and the low bits one place up
    slli    t1, t1, 1
    srli    t5, t2, 63
    or      t1, t1, t5
    slli    t2, t2, 1
    slli    a0, a0, 1
    bnez    t4, 2f
    bltu    t1, a1, 3f
2:  sub     t1, t1, a1
    ori     a0, a0, 1
3:  addi    t3, t3, -1
    bnez    t3, 1b
    ret
8:  li      a0, 0
    ret
9:  li      a0, -1
    ret
END_FUNCTION mt_ticks_us

# The entry s5's name. Uses a0, a1, t0, t1.
LOCAL_FUNCTION mt_name
    UNWIND_END_PROLOGUE
    lwu     a0, MetricEntry_name(s5)
    lwu     a1, MetricEntry_name_len(s5)
    j       mt_text
END_FUNCTION mt_name

# `name="value"` of the label table record a0 and value index a1. Locals: a0, a1.
LOCAL_FUNCTION mt_label
    FRAME 16
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    lwu     a1, MetricLabel_name_len(a0)
    lwu     a0, MetricLabel_name(a0)
    call    mt_text
    MT_TEXT mx_eq
    ld      t0, 0(sp)                       # the value: metrics_label_values[first + index]
    lwu     t1, MetricLabel_first(t0)
    ld      t2, 8(sp)
    add     t1, t1, t2
    slli    t1, t1, 3
    lla     t2, metrics_label_values
    add     t2, t2, t1
    lwu     a0, 0(t2)
    lwu     a1, 4(t2)
    call    mt_text
    MT_TEXT mx_quote
    UNFRAME 16
END_FUNCTION mt_label

/*
 * A sample's start: the entry s5's name, the suffix of a1 bytes at a0 (none when a1 is 0), then "{"
 * and the labels of the LabelState a2 when it has a label. a0 = 1 when a "{" went out, else 0.
 * Locals: the LabelState, the flag, the suffix, its length.
 */
LOCAL_FUNCTION mt_open
    FRAME 32
    sd      a2, 0(sp)
    sd      zero, 8(sp)
    sd      a0, 16(sp)
    sd      a1, 24(sp)
    call    mt_name
    ld      a0, 16(sp)
    ld      a1, 24(sp)
    beqz    a1, 1f
    call    mt_put
1:  ld      t0, 0(sp)
    ld      t1, LS_LABEL1(t0)
    beqz    t1, 9f
    li      t1, 1
    sd      t1, 8(sp)
    MT_TEXT mx_lbrace
    ld      t0, 0(sp)
    ld      a0, LS_LABEL1(t0)
    ld      a1, LS_I1(t0)
    call    mt_label
    ld      t0, 0(sp)
    ld      t1, LS_LABEL2(t0)
    beqz    t1, 9f
    MT_TEXT mx_comma
    ld      t0, 0(sp)
    ld      a0, LS_LABEL2(t0)
    ld      a1, LS_I2(t0)
    call    mt_label
9:  ld      a0, 8(sp)
    UNFRAME 32
END_FUNCTION mt_open

# A sample's end: "}" when a0 is 1, " ", then the decimal a1 and LF. Locals: a1.
LOCAL_FUNCTION mt_value
    FRAME 16
    sd      a1, 0(sp)
    beqz    a0, 1f
    MT_TEXT mx_rbrace
1:  MT_TEXT mx_sp
    ld      a0, 0(sp)
    call    mt_dec
    MT_TEXT mx_lf
    UNFRAME 16
END_FUNCTION mt_value

# `{` when a0 is 0, else `,`; then `le="`.
LOCAL_FUNCTION mt_le
    FRAME 0
    bnez    a0, 1f
    MT_TEXT mx_lbrace
    j       2f
1:  MT_TEXT mx_comma
2:  MT_TEXT mx_le
    MT_TEXT mx_eq
    UNFRAME 0
END_FUNCTION mt_le

/*
 * The histogram a0 of the bound set record a1, with the labels of the LabelState a2; a3 is the
 * ticks per second for a set of ticks. Locals: the Histogram, the bounds, the LabelState, the tick
 * rate, the bound index, the sum so far.
 */
LOCAL_FUNCTION mt_histogram
    FRAME 48
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      a2, 16(sp)
    sd      a3, 24(sp)
    sd      zero, 32(sp)
    sd      zero, 40(sp)
1:  ld      t0, 32(sp)                      # each bound: the values at or below it
    ld      t1, 8(sp)
    lwu     t2, MetricBounds_count(t1)
    bgeu    t0, t2, 2f
    ld      t3, 0(sp)
    slli    t4, t0, 3
    add     t3, t3, t4
    ld      t3, Histogram_buckets(t3)
    ld      t4, 40(sp)
    add     t4, t4, t3
    sd      t4, 40(sp)
    lla     a0, mx_bucket
    li      a1, mx_bucket_len
    ld      a2, 16(sp)
    call    mt_open
    call    mt_le
    ld      t0, 32(sp)                      # the bound's text
    ld      t1, 8(sp)
    lwu     t2, MetricBounds_first(t1)
    add     t2, t2, t0
    slli    t2, t2, 4
    lla     t3, metrics_bound_values
    add     t3, t3, t2
    lwu     a0, MetricBound_text(t3)
    lwu     a1, MetricBound_text_len(t3)
    call    mt_text
    MT_TEXT mx_quote
    li      a0, 1
    ld      a1, 40(sp)
    call    mt_value
    ld      t0, 32(sp)
    addi    t0, t0, 1
    sd      t0, 32(sp)
    j       1b
2:  lla     a0, mx_bucket                   # +Inf: every value
    li      a1, mx_bucket_len
    ld      a2, 16(sp)
    call    mt_open
    call    mt_le
    MT_TEXT mx_inf
    MT_TEXT mx_quote
    li      a0, 1
    ld      t0, 0(sp)
    ld      a1, Histogram_count(t0)
    call    mt_value
    lla     a0, mx_sum                      # _sum in seconds
    li      a1, mx_sum_len
    ld      a2, 16(sp)
    call    mt_open
    beqz    a0, 3f
    MT_TEXT mx_rbrace
3:  MT_TEXT mx_sp
    ld      t0, 0(sp)
    ld      a0, Histogram_sum(t0)
    ld      t1, 8(sp)
    lwu     t2, MetricBounds_unit(t1)
    li      t3, METRIC_UNIT_TICKS
    bne     t2, t3, 4f
    ld      a1, 24(sp)                      # ticks: sum * 10^6 / the rate, in microseconds
    call    mt_ticks_us
4:  call    mt_seconds
    MT_TEXT mx_lf
    lla     a0, mx_count                    # _count
    li      a1, mx_count_len
    ld      a2, 16(sp)
    call    mt_open
    ld      t0, 0(sp)
    ld      a1, Histogram_count(t0)
    call    mt_value
    UNFRAME 48
END_FUNCTION mt_histogram

# The entry s5's name and `{topic="<name>"` of the GossipTopic a0. Locals: the topic.
LOCAL_FUNCTION mt_topic
    FRAME 16
    sd      a0, 0(sp)
    call    mt_name
    MT_TEXT mx_lbrace
    MT_TEXT mx_topic
    MT_TEXT mx_eq
    ld      t0, 0(sp)
    addi    a0, t0, GossipTopic_name
    ld      a1, GossipTopic_name_length(t0)
    call    mt_put
    MT_TEXT mx_quote
    UNFRAME 16
END_FUNCTION mt_topic

# `,<name>="<value>"`: the name is a1 bytes at a0, the value a3 bytes at a2. Locals: the texts.
LOCAL_FUNCTION mt_pair
    FRAME 32
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      a2, 16(sp)
    sd      a3, 24(sp)
    MT_TEXT mx_comma
    ld      a0, 0(sp)
    ld      a1, 8(sp)
    call    mt_put
    MT_TEXT mx_eq
    ld      a0, 16(sp)
    ld      a1, 24(sp)
    call    mt_put
    MT_TEXT mx_quote
    UNFRAME 32
END_FUNCTION mt_pair

.macro MT_PAIR name, value
    lla     a0, \name
    li      a1, \name\()_len
    lla     a2, \value
    li      a3, \value\()_len
    call    mt_pair
.endm

# The element s10's label value indices into the LabelState: s10 / the second label's count, s10 % it.
.macro MT_INDICES
    ld      t0, (L + 72)(sp)
    divu    t1, s10, t0
    remu    t2, s10, t0
    sd      t1, (L + 32 + LS_I1)(sp)
    sd      t2, (L + 32 + LS_I2)(sp)
.endm

/*
 * lantern_metrics_text(categories, sources, out) -> status
 * The Prometheus text of the metrics of the categories. s1 metrics_texts, s2 the cursor, s3 the
 * end of the room, s4 1 when the room ran out, s5 a table entry, s6 the entry's value, s7 its kind,
 * s8 a gossip topic, s9 the gossip topics left, s10 the element. Locals: L the categories, L+8 the
 * sources, L+16 out, L+24 the ticks per second, L+32 a LabelState (32 bytes), L+64 the elements,
 * L+72 the second label's value count.
 */
FUNCTION lantern_metrics_text
    ENTER 80
    ld      t0, 0(a0)
    sd      t0, (L + 0)(sp)
    sd      a1, (L + 8)(sp)
    sd      a2, (L + 16)(sp)
    addi    s2, a2, 24
    ld      s3, 0(a2)
    add     s3, s3, a2
    li      s4, 0
    lla     s1, metrics_texts
    ld      t0, MetricsSources_profile(a1)  # the tick rate: the Profile's, or 0
    beqz    t0, 1f
    ld      t0, Profile_ticks_per_second(t0)
1:  sd      t0, (L + 24)(sp)
    lla     s5, metrics_table
10: lla     t0, metrics_table_end
    bgeu    s5, t0, 90f
    lwu     t0, MetricEntry_bit(s5)         # its category
    ld      t1, (L + 0)(sp)
    srl     t1, t1, t0
    andi    t1, t1, 1
    beqz    t1, 80f
    lwu     t0, MetricEntry_source(s5)      # its source, given
    ld      t1, (L + 8)(sp)
    slli    t0, t0, 3
    add     t0, t1, t0
    ld      s6, 0(t0)
    beqz    s6, 80f
    lhu     t0, MetricEntry_cond(s5)        # its condition
    ld      t2, MetricsSources_state(t1)
    li      t3, METRIC_COND_NONE
    beq     t0, t3, 20f
    li      t3, METRIC_COND_STATE
    beq     t0, t3, 11f
    li      t3, METRIC_COND_ELECTRA
    beq     t0, t3, 12f
    li      t3, METRIC_COND_STATE_ROOT
    beq     t0, t3, 13f
    li      t3, METRIC_COND_FULU
    beq     t0, t3, 14f
    li      t3, METRIC_COND_MAX_FDS
    beq     t0, t3, 15f
    li      t3, METRIC_COND_ALTAIR
    beq     t0, t3, 16f
    ld      t4, (L + 24)(sp)                # METRIC_COND_PROFILE: a tick rate
    beqz    t4, 80f
    j       20f
11: beqz    t2, 80f
    ld      t4, MetricsState_present(t2)
    beqz    t4, 80f
    j       20f
12: beqz    t2, 80f
    ld      t4, MetricsState_present(t2)
    beqz    t4, 80f
    ld      t4, MetricsState_electra(t2)
    beqz    t4, 80f
    j       20f
16: beqz    t2, 80f
    ld      t4, MetricsState_present(t2)
    beqz    t4, 80f
    ld      t4, MetricsState_altair(t2)
    beqz    t4, 80f
    j       20f
13: beqz    t2, 80f
    ld      t4, MetricsState_present(t2)
    beqz    t4, 80f
    ld      t4, MetricsState_state_root_present(t2)
    beqz    t4, 80f
    j       20f
14: ld      t2, MetricsSources_node(t1)
    beqz    t2, 80f
    ld      t4, MetricsNode_fulu(t2)
    beqz    t4, 80f
    j       20f
15: ld      t2, MetricsSources_process(t1)
    beqz    t2, 80f
    ld      t4, MetricsProcess_max_fds(t2)
    beqz    t4, 80f
20: lhu     s7, MetricEntry_kind(s5)        # a gossipsub family with no sample does not go out
    li      t2, METRIC_KIND_GOSSIP_MAIN
    bltu    s7, t2, 30f
    PART    t1, t3, s6, MetricsGossip_topics
21: beqz    t3, 80f
    bne     s7, t2, 30f
    ld      t4, GossipTopic_subnet(t1)
    beqz    t4, 30f
    addi    t1, t1, GossipTopic__mem
    addi    t3, t3, -1
    j       21b
30: MT_TEXT mx_help                         # # HELP <name> <help>, # TYPE <name> <type>
    call    mt_name
    MT_TEXT mx_sp
    lwu     a0, MetricEntry_help(s5)
    lwu     a1, MetricEntry_help_len(s5)
    call    mt_text
    MT_TEXT mx_lf
    MT_TEXT mx_type
    call    mt_name
    lwu     t0, MetricEntry_type(s5)
    li      t1, METRIC_TYPE_COUNTER
    beq     t0, t1, 31f
    bgtu    t0, t1, 32f
    MT_TEXT mx_gauge
    j       33f
31: MT_TEXT mx_counter
    j       33f
32: MT_TEXT mx_histogram
33: lwu     t0, MetricEntry_offset(s5)      # its value in its source; its label tables
    add     s6, s6, t0
    sd      zero, (L + 32 + LS_LABEL1)(sp)
    sd      zero, (L + 32 + LS_LABEL2)(sp)
    sd      zero, (L + 32 + LS_I1)(sp)
    sd      zero, (L + 32 + LS_I2)(sp)
    li      s10, 0
    li      t0, 1
    sd      t0, (L + 72)(sp)
    lla     t1, metrics_labels
    lhu     t0, MetricEntry_label1(s5)
    beqz    t0, 34f
    addi    t0, t0, -1
    slli    t0, t0, 4
    add     t0, t1, t0
    sd      t0, (L + 32 + LS_LABEL1)(sp)
    lhu     t0, MetricEntry_label2(s5)
    beqz    t0, 34f
    addi    t0, t0, -1
    slli    t0, t0, 4
    add     t0, t1, t0
    sd      t0, (L + 32 + LS_LABEL2)(sp)
    lwu     t0, MetricLabel_count(t0)
    sd      t0, (L + 72)(sp)
34: lwu     t0, MetricEntry_count(s5)
    sd      t0, (L + 64)(sp)
    li      t0, METRIC_KIND_U64
    beq     s7, t0, 40f
    li      t0, METRIC_KIND_ROOT
    beq     s7, t0, 41f
    li      t0, METRIC_KIND_SECONDS
    beq     s7, t0, 42f
    li      t0, METRIC_KIND_ARRAY
    beq     s7, t0, 43f
    li      t0, METRIC_KIND_HIST
    beq     s7, t0, 44f
    li      t0, METRIC_KIND_ARRAY_HIST
    beq     s7, t0, 44f
    j       50f
40: li      a0, 0                           # a value
    li      a1, 0
    addi    a2, sp, (L + 32)
    call    mt_open
    ld      a1, 0(s6)
    call    mt_value
    j       80f
41: call    mt_name                         # a root, signed
    MT_TEXT mx_sp
    ld      a0, 0(s6)
    call    mt_sdec
    MT_TEXT mx_lf
    j       80f
42: call    mt_name                         # microseconds as seconds
    MT_TEXT mx_sp
    ld      a0, 0(s6)
    call    mt_seconds
    MT_TEXT mx_lf
    j       80f
43: ld      t0, (L + 64)(sp)                # values by labels: element e at e * 8
    bgeu    s10, t0, 80f
    MT_INDICES
    li      a0, 0
    li      a1, 0
    addi    a2, sp, (L + 32)
    call    mt_open
    slli    t0, s10, 3
    add     t0, s6, t0
    ld      a1, 0(t0)
    call    mt_value
    addi    s10, s10, 1
    j       43b
44: ld      t0, (L + 64)(sp)                # histograms by labels: element e at e * Histogram__mem
    bgeu    s10, t0, 80f
    MT_INDICES
    li      t0, Histogram__mem
    mul     a0, s10, t0
    add     a0, a0, s6
    lhu     t0, MetricEntry_bounds(s5)
    slli    t0, t0, 4
    lla     a1, metrics_bounds
    add     a1, a1, t0
    addi    a2, sp, (L + 32)
    ld      a3, (L + 24)(sp)
    call    mt_histogram
    addi    s10, s10, 1
    j       44b
50: PART    s8, s9, s6, MetricsGossip_topics  # gossipsub: each topic
51: beqz    s9, 80f
    li      t0, METRIC_KIND_GOSSIP_MAIN
    bne     s7, t0, 52f
    ld      t0, GossipTopic_subnet(s8)      # main topics only
    bnez    t0, 59f
    mv      a0, s8
    call    mt_topic
    li      a0, 1
    ld      a1, GossipTopic_mesh_peers(s8)
    call    mt_value
    j       59f
52: li      t0, METRIC_KIND_GOSSIP_SENT
    bne     s7, t0, 53f
    mv      a0, s8
    call    mt_topic
    MT_PAIR mx_partial, mx_false
    li      a0, 1
    ld      a1, GossipTopic_sent_bytes(s8)
    call    mt_value
    mv      a0, s8
    call    mt_topic
    MT_PAIR mx_partial, mx_true
    li      a0, 1
    ld      a1, GossipTopic_sent_partial_bytes(s8)
    call    mt_value
    j       59f
53: mv      a0, s8                          # mesh peers by partial support
    call    mt_topic
    MT_PAIR mx_supports, mx_false
    li      a0, 1
    ld      a1, GossipTopic_mesh_peers(s8)
    ld      t0, GossipTopic_mesh_partial_peers(s8)
    sub     a1, a1, t0
    call    mt_value
    mv      a0, s8
    call    mt_topic
    MT_PAIR mx_supports, mx_true
    li      a0, 1
    ld      a1, GossipTopic_mesh_partial_peers(s8)
    call    mt_value
59: addi    s8, s8, GossipTopic__mem
    addi    s9, s9, -1
    j       51b
80: addi    s5, s5, MetricEntry__mem
    j       10b
90: bnez    s4, 91f                         # the text's length, or no room
    ld      t0, (L + 16)(sp)
    li      t1, 24
    sd      t1, 8(t0)
    addi    t1, t0, 24
    sub     t1, s2, t1
    sd      t1, 16(t0)
    li      a0, LANTERN_OK
    LEAVE 80
91: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
END_FUNCTION lantern_metrics_text
