/*
 * Metrics, RISC-V: in the common object. Requirements: docs/reference/metrics.md.
 *
 * The writers keep the cursor in s2 and the end of the room in s3; s4 becomes 1 when the room
 * runs out, and nothing is written from then on. s1 holds metrics_texts.
 */

    RODATA
.include "metrics_table.inc"

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

# The entry s5's name. Uses a0, a1, t0, t1.
LOCAL_FUNCTION mt_name
    UNWIND_END_PROLOGUE
    lwu     a0, MetricEntry_name(s5)
    lwu     a1, MetricEntry_name_len(s5)
    j       mt_text
END_FUNCTION mt_name

/*
 * A histogram's samples: the entry s5, its Histogram at a0 and its bounds table at a1. Locals:
 * the Histogram, the bounds, the bound index, the sum so far.
 */
LOCAL_FUNCTION mt_histogram
    FRAME 32
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      zero, 16(sp)
    sd      zero, 24(sp)
1:  ld      t0, 16(sp)                      # each bound: the values at or below it
    ld      t1, 8(sp)
    ld      t2, 0(t1)
    bgeu    t0, t2, 2f
    ld      t3, 0(sp)
    slli    t4, t0, 3
    add     t3, t3, t4
    ld      t3, Histogram_buckets(t3)
    ld      t4, 24(sp)
    add     t4, t4, t3
    sd      t4, 24(sp)
    call    mt_name
    MT_TEXT mx_bucket
    ld      t0, 16(sp)
    ld      t1, 8(sp)
    slli    t0, t0, 4
    add     t1, t1, t0
    lwu     a0, 16(t1)                      # its text: offset, length
    lwu     a1, 20(t1)
    call    mt_text
    MT_TEXT mx_le_end
    ld      a0, 24(sp)
    call    mt_dec
    MT_TEXT mx_lf
    ld      t0, 16(sp)
    addi    t0, t0, 1
    sd      t0, 16(sp)
    j       1b
2:  call    mt_name                         # +Inf: every value
    MT_TEXT mx_bucket
    MT_TEXT mx_inf
    MT_TEXT mx_le_end
    ld      t0, 0(sp)
    ld      a0, Histogram_count(t0)
    call    mt_dec
    MT_TEXT mx_lf
    call    mt_name                         # _sum in seconds, _count
    MT_TEXT mx_sum
    ld      t0, 0(sp)
    ld      a0, Histogram_sum_us(t0)
    call    mt_seconds
    MT_TEXT mx_lf
    call    mt_name
    MT_TEXT mx_count
    ld      t0, 0(sp)
    ld      a0, Histogram_count(t0)
    call    mt_dec
    MT_TEXT mx_lf
    UNFRAME 32
END_FUNCTION mt_histogram

# The topic label of the GossipTopic a0: `{topic="<name>`. Locals: the entry.
LOCAL_FUNCTION mt_topic
    FRAME 16
    sd      a0, 0(sp)
    call    mt_name
    MT_TEXT mx_topic
    ld      t0, 0(sp)
    addi    a0, t0, GossipTopic_name
    ld      a1, GossipTopic_name_length(t0)
    call    mt_put
    UNFRAME 16
END_FUNCTION mt_topic

/*
 * lantern_metrics_text(categories, state, node, app, process, gossip, out) -> status
 * The Prometheus text of the metrics of the categories. s1 metrics_texts, s2 the cursor, s3 the
 * end of the room, s4 1 when the room ran out, s5 a table entry, s6 the entry's source, s7 the
 * gossip kind, s8 a gossip entry, s9 the gossip entries left. Locals: L the sources by
 * METRIC_SRC_* (state, node, app, process, gossip), L+40 out.
 */
FUNCTION lantern_metrics_text
    ENTER 48
    sd      a1, (L + 0)(sp)
    sd      a2, (L + 8)(sp)
    sd      a3, (L + 16)(sp)
    sd      a4, (L + 24)(sp)
    sd      a5, (L + 32)(sp)
    sd      a6, (L + 40)(sp)
    ld      t6, 0(a0)
    addi    s2, a6, 24
    ld      s3, 0(a6)
    add     s3, s3, a6
    li      s4, 0
    lla     s1, metrics_texts
    andi    t6, t6, METRICS_BEACON
    beqz    t6, 90f
    lla     s5, metrics_table
1:  lla     t0, metrics_table_end
    bgeu    s5, t0, 90f
    lwu     t0, MetricEntry_source(s5)      # its source
    slli    t0, t0, 3
    add     t0, sp, t0
    ld      s6, L(t0)
    lhu     t0, MetricEntry_cond(s5)        # its condition
    li      t2, METRIC_COND_NONE
    beq     t0, t2, 10f
    ld      t1, (L + 0)(sp)                 # MetricsState
    li      t2, METRIC_COND_STATE
    bne     t0, t2, 2f
    ld      t3, MetricsState_present(t1)
    beqz    t3, 80f
    j       10f
2:  li      t2, METRIC_COND_ELECTRA
    bne     t0, t2, 3f
    ld      t3, MetricsState_present(t1)
    beqz    t3, 80f
    ld      t3, MetricsState_electra(t1)
    beqz    t3, 80f
    j       10f
3:  ld      t1, (L + 8)(sp)                 # MetricsNode
    li      t2, METRIC_COND_FULU
    bne     t0, t2, 4f
    ld      t3, MetricsNode_fulu(t1)
    beqz    t3, 80f
    j       10f
4:  li      t2, METRIC_COND_STATE_ROOT
    bne     t0, t2, 5f
    ld      t1, (L + 0)(sp)                 # MetricsState
    ld      t3, MetricsState_present(t1)
    beqz    t3, 80f
    ld      t3, MetricsState_state_root_present(t1)
    beqz    t3, 80f
    j       10f
5:  ld      t1, (L + 24)(sp)                # MetricsProcess: METRIC_COND_MAX_FDS
    ld      t3, MetricsProcess_max_fds(t1)
    beqz    t3, 80f
10: lhu     t0, MetricEntry_kind(s5)        # a gossipsub metric with no sample goes out
    li      t2, METRIC_KIND_GOSSIP_MAIN
    bltu    t0, t2, 20f
    PART    t1, t3, s6, MetricsGossip_topics
11: beqz    t3, 80f
    bne     t0, t2, 20f
    ld      t4, GossipTopic_subnet(t1)
    beqz    t4, 20f
    addi    t1, t1, GossipTopic__mem
    addi    t3, t3, -1
    j       11b
20: MT_TEXT mx_help                         # # HELP <name> <help>, # TYPE <name> <type>
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
    beq     t0, t1, 22f
    bgtu    t0, t1, 23f
    MT_TEXT mx_gauge
    j       24f
22: MT_TEXT mx_counter
    j       24f
23: MT_TEXT mx_histogram
24: lwu     t0, MetricEntry_offset(s5)      # its samples
    add     s6, s6, t0                      # the value, in its source
    lhu     t0, MetricEntry_kind(s5)
    li      t1, METRIC_KIND_U64
    bne     t0, t1, 30f
    call    mt_name
    MT_TEXT mx_sp
    ld      a0, 0(s6)
    call    mt_dec
    MT_TEXT mx_lf
    j       80f
30: li      t1, METRIC_KIND_ROOT
    bne     t0, t1, 31f
    call    mt_name
    MT_TEXT mx_sp
    ld      a0, 0(s6)
    call    mt_sdec
    MT_TEXT mx_lf
    j       80f
31: li      t1, METRIC_KIND_SECONDS
    bne     t0, t1, 32f
    call    mt_name
    MT_TEXT mx_sp
    ld      a0, 0(s6)
    call    mt_seconds
    MT_TEXT mx_lf
    j       80f
32: li      t1, METRIC_KIND_STATUS
    bne     t0, t1, 33f
    call    mt_name
    MT_TEXT mx_st_pending
    ld      a0, 0(s6)
    call    mt_dec
    MT_TEXT mx_lf
    call    mt_name
    MT_TEXT mx_st_active
    ld      a0, 8(s6)
    call    mt_dec
    MT_TEXT mx_lf
    call    mt_name
    MT_TEXT mx_st_exited
    ld      a0, 16(s6)
    call    mt_dec
    MT_TEXT mx_lf
    call    mt_name
    MT_TEXT mx_st_withdrawable
    ld      a0, 24(s6)
    call    mt_dec
    MT_TEXT mx_lf
    j       80f
33: li      t1, METRIC_KIND_HIST_DEFAULT
    bne     t0, t1, 34f
    lla     a1, mb_default
    j       36f
34: li      t1, METRIC_KIND_HIST_KZG
    bne     t0, t1, 35f
    lla     a1, mb_kzg
    j       36f
35: li      t1, METRIC_KIND_HIST_DELAY
    bne     t0, t1, 40f
    lla     a1, mb_delay
36: mv      a0, s6
    call    mt_histogram
    j       80f
40: mv      s7, t0                          # gossipsub: each topic
    lwu     t0, MetricEntry_offset(s5)
    sub     s6, s6, t0                      # the MetricsGossip again
    PART    s8, s9, s6, MetricsGossip_topics
41: beqz    s9, 80f
    li      t0, METRIC_KIND_GOSSIP_MAIN
    bne     s7, t0, 42f
    ld      t1, GossipTopic_subnet(s8)      # main topics only
    bnez    t1, 49f
    mv      a0, s8
    call    mt_topic
    MT_TEXT mx_topic_end
    ld      a0, GossipTopic_mesh_peers(s8)
    call    mt_dec
    MT_TEXT mx_lf
    j       49f
42: li      t0, METRIC_KIND_GOSSIP_SENT
    bne     s7, t0, 43f
    mv      a0, s8
    call    mt_topic
    MT_TEXT mx_partial_f
    ld      a0, GossipTopic_sent_bytes(s8)
    call    mt_dec
    MT_TEXT mx_lf
    mv      a0, s8
    call    mt_topic
    MT_TEXT mx_partial_t
    ld      a0, GossipTopic_sent_partial_bytes(s8)
    call    mt_dec
    MT_TEXT mx_lf
    j       49f
43: mv      a0, s8                          # mesh peers by partial support
    call    mt_topic
    MT_TEXT mx_supports_f
    ld      a0, GossipTopic_mesh_peers(s8)
    ld      t0, GossipTopic_mesh_partial_peers(s8)
    sub     a0, a0, t0
    call    mt_dec
    MT_TEXT mx_lf
    mv      a0, s8
    call    mt_topic
    MT_TEXT mx_supports_t
    ld      a0, GossipTopic_mesh_partial_peers(s8)
    call    mt_dec
    MT_TEXT mx_lf
49: addi    s8, s8, GossipTopic__mem
    addi    s9, s9, -1
    j       41b
80: addi    s5, s5, MetricEntry__mem
    j       1b
90: bnez    s4, 91f                         # the text's length, or no room
    ld      t0, (L + 40)(sp)
    li      t1, 24
    sd      t1, 8(t0)
    addi    t1, t0, 24
    sub     t1, s2, t1
    sd      t1, 16(t0)
    li      a0, LANTERN_OK
    LEAVE 48
91: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
END_FUNCTION lantern_metrics_text
