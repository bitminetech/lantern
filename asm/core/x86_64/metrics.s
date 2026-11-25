/*
 * Metrics, x86-64: in the common object. Requirements: docs/reference/metrics.md.
 *
 * The writers keep the cursor in r12 and the end of the room in r13; r15 becomes 1 when the room
 * runs out, and nothing is written from then on. rbx holds metrics_texts. A LabelState (LS_*) holds
 * the label tables of a family and the element's value index in each.
 */

    RODATA
.include "metrics_table.inc"

.set LS_LABEL1, 0                       /* the first label table's record, or 0 */
.set LS_LABEL2, 8                       /* the second's, or 0 */
.set LS_I1, 16                          /* the value index in the first */
.set LS_I2, 24                          /* the value index in the second */

/* The rsi bytes at rdi go to the cursor. Uses rax, rcx, rsi, rdi. */
LOCAL_FUNCTION lantern_mt_put
    UNWIND_END_PROLOGUE
    test    %r15, %r15
    jnz     9f
    lea     (%r12,%rsi), %rax
    cmp     %r13, %rax
    ja      8f
    mov     %rsi, %rcx
    mov     %rdi, %rsi
    mov     %r12, %rdi
    rep movsb
    mov     %rdi, %r12
    ret
8:  mov     $1, %r15d
9:  ret
END_FUNCTION lantern_mt_put

/* The text at metrics_texts + rdi, of rsi bytes. Uses rax, rcx, rsi, rdi. */
LOCAL_FUNCTION lantern_mt_text
    UNWIND_END_PROLOGUE
    add     %rbx, %rdi
    jmp     lantern_mt_put
END_FUNCTION lantern_mt_text

.macro MT_TEXT label
    lea     \label(%rip), %rdi
    mov     $\label\()_len, %esi
    call    lantern_mt_put
.endm

/* The decimal digits of rdi. Locals: the digits, from the end. Uses rax, rcx, rdx, rsi, rdi, r8. */
LOCAL_FUNCTION lantern_mt_dec
    FRAME 32
    lea     32(%rsp), %r8
    mov     %rdi, %rax
    mov     $10, %ecx
1:  xor     %edx, %edx
    div     %rcx
    add     $0x30, %dl
    dec     %r8
    mov     %dl, (%r8)
    test    %rax, %rax
    jnz     1b
    mov     %r8, %rdi
    lea     32(%rsp), %rsi
    sub     %r8, %rsi
    call    lantern_mt_put
    UNFRAME 32
END_FUNCTION lantern_mt_dec

/* rdi as a signed decimal. Locals: rdi. */
LOCAL_FUNCTION lantern_mt_sdec
    FRAME 16
    mov     %rdi, (%rsp)
    test    %rdi, %rdi
    jns     1f
    movb    $0x2d, 8(%rsp)                  # "-", then the digits of 0 - rdi (2^63 stays 2^63, unsigned)
    lea     8(%rsp), %rdi
    mov     $1, %esi
    call    lantern_mt_put
    negq    (%rsp)
1:  mov     (%rsp), %rdi
    call    lantern_mt_dec
    UNFRAME 16
END_FUNCTION lantern_mt_sdec

/* The microseconds rdi as seconds: the whole seconds, ".", six digits. Locals: rdi, the digits. */
LOCAL_FUNCTION lantern_mt_seconds
    FRAME 32
    mov     %rdi, %rax
    xor     %edx, %edx
    mov     $1000000, %ecx
    div     %rcx
    mov     %rdx, (%rsp)
    mov     %rax, %rdi
    call    lantern_mt_dec
    movb    $0x2e, 8(%rsp)                  # "."
    mov     (%rsp), %rax                    # six digits, from the end
    mov     $10, %ecx
    mov     $6, %r8d
1:  xor     %edx, %edx
    div     %rcx
    add     $0x30, %dl
    mov     %dl, 8(%rsp,%r8)
    dec     %r8
    jnz     1b
    lea     8(%rsp), %rdi
    mov     $7, %esi
    call    lantern_mt_put
    UNFRAME 32
END_FUNCTION lantern_mt_seconds

/* The entry r14's name. Uses rax, rcx, rsi, rdi. */
LOCAL_FUNCTION lantern_mt_name
    UNWIND_END_PROLOGUE
    mov     MetricEntry_name(%r14), %edi
    mov     MetricEntry_name_len(%r14), %esi
    jmp     lantern_mt_text
END_FUNCTION lantern_mt_name

/*
 * lantern_metrics_observe(histogram, bounds, value) -> status
 * The value joins the Histogram of the bound set bounds (METRIC_BOUNDS_*, of microseconds): count,
 * sum, and the bucket of the first bound at or above it, else the last. A leaf.
 */
LEAF lantern_metrics_observe
    mov     (%rsi), %rsi
    mov     (%rdx), %rdx
    incq    Histogram_count(%rdi)
    add     %rdx, Histogram_sum(%rdi)
    shl     $4, %rsi
    lea     metrics_bounds(%rip), %rax
    add     %rax, %rsi
    mov     MetricBounds_count(%rsi), %ecx
    mov     MetricBounds_first(%rsi), %eax
    shl     $4, %rax
    lea     metrics_bound_values(%rip), %r8
    add     %rax, %r8
    xor     %eax, %eax
1:  cmp     %rcx, %rax
    jae     2f
    cmp     MetricBound_value(%r8), %rdx
    jbe     2f
    add     $MetricBound__mem, %r8
    inc     %rax
    jmp     1b
2:  incq    Histogram_buckets(%rdi,%rax,8)
    xor     %eax, %eax
    ret
END_FUNCTION lantern_metrics_observe

/* `name="value"` of the label table record rdi and value index rsi. Locals: rdi, rsi. */
LOCAL_FUNCTION lantern_mt_label
    FRAME 16
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     MetricLabel_name(%rdi), %eax
    mov     MetricLabel_name_len(%rdi), %esi
    mov     %rax, %rdi
    call    lantern_mt_text
    MT_TEXT mx_eq
    mov     (%rsp), %rdi                    # the value: metrics_label_values[first + index]
    mov     MetricLabel_first(%rdi), %eax
    add     8(%rsp), %rax
    lea     metrics_label_values(%rip), %rcx
    mov     (%rcx,%rax,8), %edi
    mov     4(%rcx,%rax,8), %esi
    call    lantern_mt_text
    MT_TEXT mx_quote
    UNFRAME 16
END_FUNCTION lantern_mt_label

/*
 * A sample's start: the entry r14's name, the suffix of rsi bytes at rdi (none when rsi is 0), then
 * "{" and the labels of the LabelState rdx when it has a label. rax = 1 when a "{" went out, else 0.
 * Locals: the LabelState, the flag, the suffix, its length.
 */
LOCAL_FUNCTION lantern_mt_open
    FRAME 32
    mov     %rdx, (%rsp)
    movq    $0, 8(%rsp)
    mov     %rdi, 16(%rsp)
    mov     %rsi, 24(%rsp)
    call    lantern_mt_name
    mov     24(%rsp), %rsi
    test    %rsi, %rsi
    jz      1f
    mov     16(%rsp), %rdi
    call    lantern_mt_put
1:  mov     (%rsp), %rax
    cmpq    $0, LS_LABEL1(%rax)
    je      9f
    movq    $1, 8(%rsp)
    MT_TEXT mx_lbrace
    mov     (%rsp), %rax
    mov     LS_LABEL1(%rax), %rdi
    mov     LS_I1(%rax), %rsi
    call    lantern_mt_label
    mov     (%rsp), %rax
    cmpq    $0, LS_LABEL2(%rax)
    je      9f
    MT_TEXT mx_comma
    mov     (%rsp), %rax
    mov     LS_LABEL2(%rax), %rdi
    mov     LS_I2(%rax), %rsi
    call    lantern_mt_label
9:  mov     8(%rsp), %rax
    UNFRAME 32
END_FUNCTION lantern_mt_open

/* A sample's end: "}" when rdi is 1, " ", then the decimal rsi and LF. Locals: rsi. */
LOCAL_FUNCTION lantern_mt_value
    FRAME 16
    mov     %rsi, (%rsp)
    test    %rdi, %rdi
    jz      1f
    MT_TEXT mx_rbrace
1:  MT_TEXT mx_sp
    mov     (%rsp), %rdi
    call    lantern_mt_dec
    MT_TEXT mx_lf
    UNFRAME 16
END_FUNCTION lantern_mt_value

/* `{` when rdi is 0, else `,`; then `le="`. Uses rax, rcx, rsi, rdi. */
LOCAL_FUNCTION lantern_mt_le
    FRAME 0
    test    %rdi, %rdi
    jnz     1f
    MT_TEXT mx_lbrace
    jmp     2f
1:  MT_TEXT mx_comma
2:  MT_TEXT mx_le
    MT_TEXT mx_eq
    UNFRAME 0
END_FUNCTION lantern_mt_le

/*
 * The histogram rdi of the bound set record rsi, with the labels of the LabelState rdx; rcx is the
 * ticks per second for a set of ticks. Locals: the Histogram, the bounds, the LabelState, the tick
 * rate, the bound index, the sum so far.
 */
LOCAL_FUNCTION lantern_mt_histogram
    FRAME 48
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    mov     %rcx, 24(%rsp)
    movq    $0, 32(%rsp)
    movq    $0, 40(%rsp)
1:  mov     32(%rsp), %rax                  # each bound: the values at or below it
    mov     8(%rsp), %rcx
    mov     MetricBounds_count(%rcx), %ecx
    cmp     %rcx, %rax
    jae     2f
    mov     (%rsp), %rdx
    mov     Histogram_buckets(%rdx,%rax,8), %rdx
    add     %rdx, 40(%rsp)
    lea     mx_bucket(%rip), %rdi
    mov     $mx_bucket_len, %esi
    mov     16(%rsp), %rdx
    call    lantern_mt_open
    mov     %rax, %rdi
    call    lantern_mt_le
    mov     8(%rsp), %rcx                   # the bound's text
    mov     MetricBounds_first(%rcx), %eax
    add     32(%rsp), %rax
    shl     $4, %rax
    lea     metrics_bound_values(%rip), %rcx
    mov     MetricBound_text(%rcx,%rax), %edi
    mov     MetricBound_text_len(%rcx,%rax), %esi
    call    lantern_mt_text
    MT_TEXT mx_quote
    mov     $1, %edi
    mov     40(%rsp), %rsi
    call    lantern_mt_value
    incq    32(%rsp)
    jmp     1b
2:  lea     mx_bucket(%rip), %rdi           # +Inf: every value
    mov     $mx_bucket_len, %esi
    mov     16(%rsp), %rdx
    call    lantern_mt_open
    mov     %rax, %rdi
    call    lantern_mt_le
    MT_TEXT mx_inf
    MT_TEXT mx_quote
    mov     $1, %edi
    mov     (%rsp), %rax
    mov     Histogram_count(%rax), %rsi
    call    lantern_mt_value
    lea     mx_sum(%rip), %rdi              # _sum in seconds
    mov     $mx_sum_len, %esi
    mov     16(%rsp), %rdx
    call    lantern_mt_open
    test    %rax, %rax
    jz      3f
    MT_TEXT mx_rbrace
3:  MT_TEXT mx_sp
    mov     (%rsp), %rax
    mov     Histogram_sum(%rax), %rdi
    mov     8(%rsp), %rcx
    cmpl    $METRIC_UNIT_TICKS, MetricBounds_unit(%rcx)
    jne     5f
    mov     24(%rsp), %rcx                  # ticks: sum * 10^6 / the rate, in microseconds
    xor     %eax, %eax
    test    %rcx, %rcx
    jz      4f
    mov     %rdi, %rax
    mov     $1000000, %edx
    mul     %rdx
    cmp     %rcx, %rdx                      # a quotient of 2^64 or more: the largest u64
    jae     6f
    div     %rcx
    jmp     4f
6:  mov     $-1, %rax
4:  mov     %rax, %rdi
5:  call    lantern_mt_seconds
    MT_TEXT mx_lf
    lea     mx_count(%rip), %rdi            # _count
    mov     $mx_count_len, %esi
    mov     16(%rsp), %rdx
    call    lantern_mt_open
    mov     %rax, %rdi
    mov     (%rsp), %rax
    mov     Histogram_count(%rax), %rsi
    call    lantern_mt_value
    UNFRAME 48
END_FUNCTION lantern_mt_histogram

/* The entry r14's name and `{topic="<name>"` of the GossipTopic rdi. Locals: the topic. */
LOCAL_FUNCTION lantern_mt_topic
    FRAME 16
    mov     %rdi, (%rsp)
    call    lantern_mt_name
    MT_TEXT mx_lbrace
    MT_TEXT mx_topic
    MT_TEXT mx_eq
    mov     (%rsp), %rax
    lea     GossipTopic_name(%rax), %rdi
    mov     GossipTopic_name_length(%rax), %rsi
    call    lantern_mt_put
    MT_TEXT mx_quote
    UNFRAME 16
END_FUNCTION lantern_mt_topic

/* `,<name>="<value>"`: the name is rsi bytes at rdi, the value rcx bytes at rdx. Locals: the texts. */
LOCAL_FUNCTION lantern_mt_pair
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    mov     %rcx, 24(%rsp)
    MT_TEXT mx_comma
    mov     (%rsp), %rdi
    mov     8(%rsp), %rsi
    call    lantern_mt_put
    MT_TEXT mx_eq
    mov     16(%rsp), %rdi
    mov     24(%rsp), %rsi
    call    lantern_mt_put
    MT_TEXT mx_quote
    UNFRAME 32
END_FUNCTION lantern_mt_pair

.macro MT_PAIR name, value
    lea     \name(%rip), %rdi
    mov     $\name\()_len, %esi
    lea     \value(%rip), %rdx
    mov     $\value\()_len, %ecx
    call    lantern_mt_pair
.endm

/*
 * lantern_metrics_text(categories, sources, out) -> status
 * The Prometheus text of the metrics of the categories. rbx metrics_texts, r12 the cursor, r13 the
 * end of the room, r14 a table entry, r15 1 when the room ran out, rbp the entry's value. Locals: L
 * the categories, L+8 the sources, L+16 out, L+24 the ticks per second, L+32 a LabelState (32 bytes),
 * L+64 the element, L+72 the elements, L+80 the second label's value count, L+88 the kind, L+96 a
 * gossip topic, L+104 the gossip topics left.
 */
FUNCTION lantern_metrics_text
    ENTER 112
    mov     (%rdi), %rdi
    mov     %rdi, L(%rsp)
    mov     %rsi, (L + 8)(%rsp)
    mov     %rdx, (L + 16)(%rsp)
    lea     24(%rdx), %r12
    mov     (%rdx), %r13
    add     %rdx, %r13
    xor     %r15d, %r15d
    lea     metrics_texts(%rip), %rbx
    movq    $0, (L + 24)(%rsp)              # the tick rate: the Profile's, or 0
    mov     MetricsSources_profile(%rsi), %rax
    test    %rax, %rax
    jz      1f
    mov     Profile_ticks_per_second(%rax), %rax
    mov     %rax, (L + 24)(%rsp)
1:  lea     metrics_table(%rip), %r14
10: lea     metrics_table_end(%rip), %rax
    cmp     %rax, %r14
    jae     90f
    mov     MetricEntry_bit(%r14), %eax     # its category
    mov     L(%rsp), %rcx
    bt      %rax, %rcx
    jnc     80f
    mov     MetricEntry_source(%r14), %eax  # its source, given
    mov     (L + 8)(%rsp), %rcx
    mov     (%rcx,%rax,8), %rbp
    test    %rbp, %rbp
    jz      80f
    movzwl  MetricEntry_cond(%r14), %eax    # its condition
    mov     MetricsSources_state(%rcx), %rdx
    cmp     $METRIC_COND_NONE, %eax
    je      20f
    cmp     $METRIC_COND_STATE, %eax
    je      11f
    cmp     $METRIC_COND_ELECTRA, %eax
    je      12f
    cmp     $METRIC_COND_STATE_ROOT, %eax
    je      13f
    cmp     $METRIC_COND_FULU, %eax
    je      14f
    cmp     $METRIC_COND_MAX_FDS, %eax
    je      15f
    cmp     $METRIC_COND_ALTAIR, %eax
    je      16f
    cmpq    $0, (L + 24)(%rsp)              # METRIC_COND_PROFILE: a tick rate
    je      80f
    jmp     20f
11: test    %rdx, %rdx
    jz      80f
    cmpq    $0, MetricsState_present(%rdx)
    je      80f
    jmp     20f
12: test    %rdx, %rdx
    jz      80f
    cmpq    $0, MetricsState_present(%rdx)
    je      80f
    cmpq    $0, MetricsState_electra(%rdx)
    je      80f
    jmp     20f
16: test    %rdx, %rdx
    jz      80f
    cmpq    $0, MetricsState_present(%rdx)
    je      80f
    cmpq    $0, MetricsState_altair(%rdx)
    je      80f
    jmp     20f
13: test    %rdx, %rdx
    jz      80f
    cmpq    $0, MetricsState_present(%rdx)
    je      80f
    cmpq    $0, MetricsState_state_root_present(%rdx)
    je      80f
    jmp     20f
14: mov     MetricsSources_node(%rcx), %rdx
    test    %rdx, %rdx
    jz      80f
    cmpq    $0, MetricsNode_fulu(%rdx)
    je      80f
    jmp     20f
15: mov     MetricsSources_process(%rcx), %rdx
    test    %rdx, %rdx
    jz      80f
    cmpq    $0, MetricsProcess_max_fds(%rdx)
    je      80f
20: movzwl  MetricEntry_kind(%r14), %eax    # a gossipsub family with no sample does not go out
    mov     %rax, (L + 88)(%rsp)
    cmp     $METRIC_KIND_GOSSIP_MAIN, %eax
    jb      30f
    PART    %rcx, %rsi, %rbp, MetricsGossip_topics
21: test    %rsi, %rsi
    jz      80f
    cmp     $METRIC_KIND_GOSSIP_MAIN, %eax
    jne     30f
    cmpq    $0, GossipTopic_subnet(%rcx)
    je      30f
    add     $GossipTopic__mem, %rcx
    dec     %rsi
    jmp     21b
30: MT_TEXT mx_help                         # # HELP <name> <help>, # TYPE <name> <type>
    call    lantern_mt_name
    MT_TEXT mx_sp
    mov     MetricEntry_help(%r14), %edi
    mov     MetricEntry_help_len(%r14), %esi
    call    lantern_mt_text
    MT_TEXT mx_lf
    MT_TEXT mx_type
    call    lantern_mt_name
    mov     MetricEntry_type(%r14), %eax
    cmp     $METRIC_TYPE_COUNTER, %eax
    je      31f
    ja      32f
    MT_TEXT mx_gauge
    jmp     33f
31: MT_TEXT mx_counter
    jmp     33f
32: MT_TEXT mx_histogram
33: mov     MetricEntry_offset(%r14), %eax  # its value in its source; its label tables
    add     %rax, %rbp
    xor     %eax, %eax
    mov     %rax, (L + 32 + LS_LABEL1)(%rsp)
    mov     %rax, (L + 32 + LS_LABEL2)(%rsp)
    mov     %rax, (L + 32 + LS_I1)(%rsp)
    mov     %rax, (L + 32 + LS_I2)(%rsp)
    mov     %rax, (L + 64)(%rsp)
    movq    $1, (L + 80)(%rsp)
    lea     metrics_labels(%rip), %rcx
    movzwl  MetricEntry_label1(%r14), %eax
    test    %eax, %eax
    jz      34f
    dec     %eax
    shl     $4, %rax
    add     %rcx, %rax
    mov     %rax, (L + 32 + LS_LABEL1)(%rsp)
    movzwl  MetricEntry_label2(%r14), %eax
    test    %eax, %eax
    jz      34f
    dec     %eax
    shl     $4, %rax
    add     %rcx, %rax
    mov     %rax, (L + 32 + LS_LABEL2)(%rsp)
    mov     MetricLabel_count(%rax), %eax
    mov     %rax, (L + 80)(%rsp)
34: mov     MetricEntry_count(%r14), %eax
    mov     %rax, (L + 72)(%rsp)
    mov     (L + 88)(%rsp), %rax
    cmp     $METRIC_KIND_U64, %eax
    je      40f
    cmp     $METRIC_KIND_ROOT, %eax
    je      41f
    cmp     $METRIC_KIND_SECONDS, %eax
    je      42f
    cmp     $METRIC_KIND_ARRAY, %eax
    je      43f
    cmp     $METRIC_KIND_HIST, %eax
    je      44f
    cmp     $METRIC_KIND_ARRAY_HIST, %eax
    je      44f
    jmp     50f
40: xor     %edi, %edi                      # a value
    xor     %esi, %esi
    lea     (L + 32)(%rsp), %rdx
    call    lantern_mt_open
    mov     %rax, %rdi
    mov     (%rbp), %rsi
    call    lantern_mt_value
    jmp     80f
41: call    lantern_mt_name                         # a root, signed
    MT_TEXT mx_sp
    mov     (%rbp), %rdi
    call    lantern_mt_sdec
    MT_TEXT mx_lf
    jmp     80f
42: call    lantern_mt_name                         # microseconds as seconds
    MT_TEXT mx_sp
    mov     (%rbp), %rdi
    call    lantern_mt_seconds
    MT_TEXT mx_lf
    jmp     80f
43: mov     (L + 64)(%rsp), %rax            # values by labels: element e at e * 8, its label
    cmp     (L + 72)(%rsp), %rax            # values e / the second label's count, e % it
    jae     80f
    xor     %edx, %edx
    divq    (L + 80)(%rsp)
    mov     %rax, (L + 32 + LS_I1)(%rsp)
    mov     %rdx, (L + 32 + LS_I2)(%rsp)
    xor     %edi, %edi
    xor     %esi, %esi
    lea     (L + 32)(%rsp), %rdx
    call    lantern_mt_open
    mov     %rax, %rdi
    mov     (L + 64)(%rsp), %rax
    mov     (%rbp,%rax,8), %rsi
    call    lantern_mt_value
    incq    (L + 64)(%rsp)
    jmp     43b
44: mov     (L + 64)(%rsp), %rax            # histograms by labels: element e at e * Histogram__mem
    cmp     (L + 72)(%rsp), %rax
    jae     80f
    xor     %edx, %edx
    divq    (L + 80)(%rsp)
    mov     %rax, (L + 32 + LS_I1)(%rsp)
    mov     %rdx, (L + 32 + LS_I2)(%rsp)
    mov     (L + 64)(%rsp), %rax
    imul    $Histogram__mem, %rax, %rdi
    add     %rbp, %rdi
    movzwl  MetricEntry_bounds(%r14), %eax
    shl     $4, %rax
    lea     metrics_bounds(%rip), %rsi
    add     %rax, %rsi
    lea     (L + 32)(%rsp), %rdx
    mov     (L + 24)(%rsp), %rcx
    call    lantern_mt_histogram
    incq    (L + 64)(%rsp)
    jmp     44b
50: PART    %rcx, %rsi, %rbp, MetricsGossip_topics  # gossipsub: each topic
    mov     %rcx, (L + 96)(%rsp)
    mov     %rsi, (L + 104)(%rsp)
51: cmpq    $0, (L + 104)(%rsp)
    je      80f
    mov     (L + 96)(%rsp), %rbp
    mov     (L + 88)(%rsp), %rax
    cmp     $METRIC_KIND_GOSSIP_MAIN, %eax
    jne     52f
    cmpq    $0, GossipTopic_subnet(%rbp)    # main topics only
    jne     59f
    mov     %rbp, %rdi
    call    lantern_mt_topic
    mov     $1, %edi
    mov     GossipTopic_mesh_peers(%rbp), %rsi
    call    lantern_mt_value
    jmp     59f
52: cmp     $METRIC_KIND_GOSSIP_SENT, %eax
    jne     53f
    mov     %rbp, %rdi
    call    lantern_mt_topic
    MT_PAIR mx_partial, mx_false
    mov     $1, %edi
    mov     GossipTopic_sent_bytes(%rbp), %rsi
    call    lantern_mt_value
    mov     %rbp, %rdi
    call    lantern_mt_topic
    MT_PAIR mx_partial, mx_true
    mov     $1, %edi
    mov     GossipTopic_sent_partial_bytes(%rbp), %rsi
    call    lantern_mt_value
    jmp     59f
53: mov     %rbp, %rdi                      # mesh peers by partial support
    call    lantern_mt_topic
    MT_PAIR mx_supports, mx_false
    mov     $1, %edi
    mov     GossipTopic_mesh_peers(%rbp), %rsi
    sub     GossipTopic_mesh_partial_peers(%rbp), %rsi
    call    lantern_mt_value
    mov     %rbp, %rdi
    call    lantern_mt_topic
    MT_PAIR mx_supports, mx_true
    mov     $1, %edi
    mov     GossipTopic_mesh_partial_peers(%rbp), %rsi
    call    lantern_mt_value
59: addq    $GossipTopic__mem, (L + 96)(%rsp)
    decq    (L + 104)(%rsp)
    jmp     51b
80: add     $MetricEntry__mem, %r14
    jmp     10b
90: test    %r15, %r15                      # the text's length, or no room
    jnz     91f
    mov     (L + 16)(%rsp), %rax
    movq    $24, 8(%rax)
    lea     24(%rax), %rcx
    sub     %rcx, %r12
    mov     %r12, 16(%rax)
    xor     %eax, %eax
    LEAVE 112
91: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 112
END_FUNCTION lantern_metrics_text

.set MN_CHAIN, 2 * SLOTS_PER_EPOCH         /* the head's chain from the previous epoch on: at most two epochs of blocks */

/*
 * lantern_metrics_node(node, store, out) -> status
 * The node's and store's values of the metrics. rbx node, r12 store, rbp out, r13 the store's slot,
 * r14 the head's NodeBlock or 0, r15 the head's chain blocks. Locals: L their NodeBlock addresses
 * (MN_CHAIN), then the previous epoch's first slot, then the store's epoch.
 */
FUNCTION lantern_metrics_node
    ENTER (8 * MN_CHAIN + 16)
    mov     %rdi, %rbx
    mov     %rsi, %r12
    mov     %rdx, %rbp
    mov     %rbp, %rdi
    mov     $MetricsNode__mem, %esi
    call    lantern_zero
    mov     (Node_peers + 8)(%rbx), %rax
    mov     %rax, MetricsNode_peers(%rbp)
    mov     %r12, %rdi
    call    lantern_node_store_slot
    mov     %rax, %r13
    xor     %edx, %edx                      # the store's epoch: from fulu, the custody groups
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, (L + 8 * MN_CHAIN + 8)(%rsp)
    cmp     (Node_config + CONFIG_FULU_FORK_EPOCH)(%rbx), %rax
    jb      1f
    movq    $1, MetricsNode_fulu(%rbp)
    mov     Node_custody_count(%rbx), %rcx
    mov     %rcx, MetricsNode_custody_groups(%rbp)
1:  PART    %rcx, %rdx, %rbx, Node_pool     # the pool's voluntary exits
    xor     %eax, %eax
2:  test    %rdx, %rdx                  # and the pool's entries by topic
    jz      3f
    mov     NodePool_topic(%rcx), %r8
    cmp     $GOSSIP_VOLUNTARY_EXIT, %r8
    jne     20f
    inc     %rax
20: test    %r8, %r8
    jz      21f
    cmp     $GOSSIP_NAMES, %r8
    ja      21f
    incq    MetricsNode_pool(%rbp,%r8,8)
21: add     $NodePool__mem, %rcx
    dec     %rdx
    jmp     2b
3:  mov     %rax, MetricsNode_pending_exits(%rbp)
    PART    %rcx, %rdx, %rbx, Node_proposers  # the proposers that hold: until_epoch above the store's epoch
    mov     (L + 8 * MN_CHAIN + 8)(%rsp), %rsi
    xor     %eax, %eax
4:  test    %rdx, %rdx
    jz      5f
    cmp     %rsi, NodeProposer_until_epoch(%rcx)
    jbe     41f
    inc     %rax
41: add     $NodeProposer__mem, %rcx
    dec     %rdx
    jmp     4b
5:  mov     %rax, MetricsNode_local_validators(%rbp)
    lea     Node_head_root(%rbx), %rdi      # the head's block: its buffers and slot
    call    lantern_node_find_block
    xor     %r14d, %r14d
    xor     %ecx, %ecx
    cmp     $-1, %rax
    je      6f
    mov     %rdx, %r14
    mov     NodeBlock_data_id(%r14), %rax
    mov     %rax, MetricsNode_head_block_id(%rbp)
    mov     NodeBlock_state_id(%r14), %rax
    mov     %rax, MetricsNode_head_state_id(%rbp)
    mov     NodeBlock_slot(%r14), %rcx
6:  inc     %rcx                            # synced: the head at most a slot behind the store's
    mov     $1, %eax
    cmp     %r13, %rcx
    jae     7f
    mov     $2, %eax                        # else syncing, with a request open
    testq   $NODE_FLAG_SYNCING, Node_flags(%rbx)
    jnz     7f
    xor     %eax, %eax                      # else synced when a peer of the node's ForkDigest has a Status
    PART    %rsi, %rdx, %rbx, Node_peers    # and none has a head above the head's slot + 1 (missed slots)
    mov     Node_fork_digest(%rbx), %r8d
61: test    %rdx, %rdx
    jz      7f
    testq   $NODE_PEER_STATUS, NodePeer_flags(%rsi)
    jz      62f
    cmp     NodePeer_fork_digest(%rsi), %r8d
    jne     62f
    cmp     NodePeer_head_slot(%rsi), %rcx
    jb      63f
    mov     $1, %eax
62: add     $NodePeer__mem, %rsi
    dec     %rdx
    jmp     61b
63: xor     %eax, %eax                      # a peer ahead: behind
7:  mov     %rax, MetricsNode_sync_state(%rbp)
    mov     %r13, MetricsNode_store_slot(%rbp)  # the sync: the head's slot and its distance to the store's
    xor     %eax, %eax
    test    %r14, %r14
    jz      71f
    mov     NodeBlock_slot(%r14), %rax
71: mov     %rax, MetricsNode_head_slot(%rbp)
    mov     %r13, %rcx
    sub     %rax, %rcx
    jae     72f
    xor     %ecx, %ecx
72: mov     %rcx, MetricsNode_distance(%rbp)
    mov     Node_dialing(%rbx), %rax
    mov     %rax, MetricsNode_dialing(%rbp)
    mov     Node_earliest_slot(%rbx), %rax
    mov     %rax, MetricsNode_earliest_slot(%rbp)
    mov     Node_backfill_slot(%rbx), %rax
    mov     %rax, MetricsNode_backfill_slot(%rbp)
    mov     Store_finalized_checkpoint(%r12), %rax
    mov     %rax, MetricsNode_finalized_epoch(%rbp)
    mov     Store_justified_checkpoint(%r12), %rax
    mov     %rax, MetricsNode_justified_epoch(%rbp)
    mov     (Node_messages + 8)(%rbx), %rax
    mov     %rax, MetricsNode_messages(%rbp)
    mov     (Node_streams + 8)(%rbx), %rax
    mov     %rax, MetricsNode_streams(%rbp)
    PART    %rcx, %rdx, %rbx, Node_peers    # the peers by direction
73: test    %rdx, %rdx
    jz      74f
    mov     NodePeer_direction(%rcx), %rax
    and     $1, %eax
    incq    MetricsNode_peer_directions(%rbp,%rax,8)
    add     $NodePeer__mem, %rcx
    dec     %rdx
    jmp     73b
74:
    mov     (L + 8 * MN_CHAIN + 8)(%rsp), %rax  # the previous epoch's first slot
    test    %rax, %rax
    jz      8f
    dec     %rax
8:  imul    $SLOTS_PER_EPOCH, %rax, %rax
    mov     %rax, (L + 8 * MN_CHAIN)(%rsp)
    xor     %r15d, %r15d                    # the head's chain from it on, by parent_root, to a gap
    mov     %r14, %rdx
9:  test    %rdx, %rdx
    jz      12f
    cmp     $MN_CHAIN, %r15
    jae     12f
    mov     NodeBlock_slot(%rdx), %rax
    cmp     (L + 8 * MN_CHAIN)(%rsp), %rax
    jb      12f
    mov     %rdx, L(%rsp,%r15,8)
    inc     %r15
    lea     NodeBlock_parent_root(%rdx), %rdi
    call    lantern_node_find_block
    cmp     $-1, %rax
    jne     9b
    xor     %edx, %edx
    jmp     9b
12: PART    %rcx, %rdx, %rbx, Node_blocks   # the imported blocks of the previous epoch off that chain
    xor     %r8d, %r8d
    mov     (L + 8 * MN_CHAIN)(%rsp), %r9
    lea     SLOTS_PER_EPOCH(%r9), %r10
13: test    %rdx, %rdx
    jz      16f
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rcx)
    jne     15f
    mov     NodeBlock_slot(%rcx), %rax
    cmp     %r9, %rax
    jb      15f
    cmp     %r10, %rax
    jae     15f
    xor     %esi, %esi
14: cmp     %r15, %rsi
    jae     141f
    cmp     L(%rsp,%rsi,8), %rcx
    je      15f
    inc     %rsi
    jmp     14b
141: inc    %r8
15: add     $NodeBlock__mem, %rcx
    dec     %rdx
    jmp     13b
16: mov     %r8, MetricsNode_orphaned_blocks(%rbp)
    xor     %eax, %eax
    LEAVE (8 * MN_CHAIN + 16)
END_FUNCTION lantern_metrics_node

/*
 * lantern_metrics_answer(bytes, categories, sources, out) -> status
 * The answer to the first request of a metrics connection's bytes. rbx metrics_texts, r12 the
 * cursor, r13 the end of the room, r15 1 when the room ran out, rbp the status, r14 out. Locals: L
 * bytes, L+8 categories, L+16 sources, L+24 HttpLimits.
 */
FUNCTION lantern_metrics_answer
    ENTER 48
    mov     %rdi, L(%rsp)
    mov     %rsi, (L + 8)(%rsp)
    mov     %rdx, (L + 16)(%rsp)
    mov     %rcx, %r14
    lea     metrics_texts(%rip), %rbx
    mov     16(%rdi), %rax                  # room: the HttpRequest of the bytes, and the head
    add     $(24 + HTTP_REQUEST_FIXED + 64 + METRICS_HEAD_ROOM), %rax
    cmp     (%r14), %rax
    ja      98f
    mov     (%r14), %rax                    # the request, in out's room
    sub     $24, %rax
    mov     %rax, 24(%r14)
    movq    $METRICS_HEAD_MAX, (L + 24)(%rsp)
    movq    $0, (L + 32)(%rsp)
    lea     (L + 24)(%rsp), %rsi
    lea     24(%r14), %rdx
    CALL_GLOBAL lantern_http_request
    cmp     $LANTERN_HTTP_MORE, %rax
    je      97f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      98f
    mov     (24 + HttpRequest_status)(%r14), %rbp
    test    %rax, %rax
    jnz     50f                             # a fault: its status
    mov     $405, %ebp
    cmpq    $HTTP_METHOD_GET, (24 + HttpRequest_method)(%r14)
    jne     50f
    mov     $404, %ebp                      # the path: /metrics
    lea     24(%r14), %rcx
    PART    %rsi, %rdx, %rcx, HttpRequest_path
    cmp     $mx_path_len, %rdx
    jne     50f
    mov     (%rsi), %rax
    cmp     mx_path(%rip), %rax
    jne     50f
    mov     (%r14), %rax                    # 200: the text after METRICS_HEAD_ROOM bytes
    sub     $METRICS_HEAD_ROOM, %rax
    mov     %rax, METRICS_HEAD_ROOM(%r14)
    mov     (L + 8)(%rsp), %rdi
    mov     (L + 16)(%rsp), %rsi
    lea     METRICS_HEAD_ROOM(%r14), %rdx
    call    lantern_metrics_text
    test    %rax, %rax
    jnz     98f
    lea     24(%r14), %r12                  # the head before it, then the text moves up to the head
    lea     METRICS_HEAD_ROOM(%r14), %r13
    xor     %r15d, %r15d
    MT_TEXT mx_http
    MT_TEXT mx_ok_head
    mov     (METRICS_HEAD_ROOM + 16)(%r14), %rdi
    call    lantern_mt_dec
    MT_TEXT mx_close
    mov     %r12, %rdi
    lea     (METRICS_HEAD_ROOM + 24)(%r14), %rsi
    mov     (METRICS_HEAD_ROOM + 16)(%r14), %rdx
    add     %rdx, %r12
    call    lantern_copy
    jmp     90f
50: lea     24(%r14), %r12                  # HTTP/1.1 <status> <reason>, Allow: GET for 405, no body
    lea     METRICS_HEAD_ROOM(%r14), %r13
    xor     %r15d, %r15d
    MT_TEXT mx_http
    mov     %rbp, %rdi
    call    lantern_mt_dec
    MT_TEXT mx_sp
    mov     %rbp, %rdi
    call    lantern_api_code
    test    %rax, %rax
    jz      51f
    mov     8(%rax), %rdi
    mov     16(%rax), %rsi
    lea     api_texts(%rip), %rcx
    add     %rcx, %rdi
    call    lantern_mt_put
51: MT_TEXT mx_crlf
    cmp     $405, %rbp
    jne     52f
    MT_TEXT mx_allow
52: MT_TEXT mx_len0
90: movq    $24, 8(%r14)                    # out: the answer's bytes
    lea     24(%r14), %rax
    sub     %rax, %r12
    mov     %r12, 16(%r14)
    xor     %eax, %eax
    LEAVE 48
97: mov     $LANTERN_HTTP_MORE, %eax
    LEAVE 48
98: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
END_FUNCTION lantern_metrics_answer
