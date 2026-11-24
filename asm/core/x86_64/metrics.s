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
LOCAL_FUNCTION mt_put
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
END_FUNCTION mt_put

/* The text at metrics_texts + rdi, of rsi bytes. Uses rax, rcx, rsi, rdi. */
LOCAL_FUNCTION mt_text
    UNWIND_END_PROLOGUE
    add     %rbx, %rdi
    jmp     mt_put
END_FUNCTION mt_text

.macro MT_TEXT label
    lea     \label(%rip), %rdi
    mov     $\label\()_len, %esi
    call    mt_put
.endm

/* The decimal digits of rdi. Locals: the digits, from the end. Uses rax, rcx, rdx, rsi, rdi, r8. */
LOCAL_FUNCTION mt_dec
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
    call    mt_put
    UNFRAME 32
END_FUNCTION mt_dec

/* rdi as a signed decimal. Locals: rdi. */
LOCAL_FUNCTION mt_sdec
    FRAME 16
    mov     %rdi, (%rsp)
    test    %rdi, %rdi
    jns     1f
    movb    $0x2d, 8(%rsp)                  # "-", then the digits of 0 - rdi (2^63 stays 2^63, unsigned)
    lea     8(%rsp), %rdi
    mov     $1, %esi
    call    mt_put
    negq    (%rsp)
1:  mov     (%rsp), %rdi
    call    mt_dec
    UNFRAME 16
END_FUNCTION mt_sdec

/* The microseconds rdi as seconds: the whole seconds, ".", six digits. Locals: rdi, the digits. */
LOCAL_FUNCTION mt_seconds
    FRAME 32
    mov     %rdi, %rax
    xor     %edx, %edx
    mov     $1000000, %ecx
    div     %rcx
    mov     %rdx, (%rsp)
    mov     %rax, %rdi
    call    mt_dec
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
    call    mt_put
    UNFRAME 32
END_FUNCTION mt_seconds

/* The entry r14's name. Uses rax, rcx, rsi, rdi. */
LOCAL_FUNCTION mt_name
    UNWIND_END_PROLOGUE
    mov     MetricEntry_name(%r14), %edi
    mov     MetricEntry_name_len(%r14), %esi
    jmp     mt_text
END_FUNCTION mt_name

/* `name="value"` of the label table record rdi and value index rsi. Locals: rdi, rsi. */
LOCAL_FUNCTION mt_label
    FRAME 16
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     MetricLabel_name(%rdi), %eax
    mov     MetricLabel_name_len(%rdi), %esi
    mov     %rax, %rdi
    call    mt_text
    MT_TEXT mx_eq
    mov     (%rsp), %rdi                    # the value: metrics_label_values[first + index]
    mov     MetricLabel_first(%rdi), %eax
    add     8(%rsp), %rax
    lea     metrics_label_values(%rip), %rcx
    mov     (%rcx,%rax,8), %edi
    mov     4(%rcx,%rax,8), %esi
    call    mt_text
    MT_TEXT mx_quote
    UNFRAME 16
END_FUNCTION mt_label

/*
 * A sample's start: the entry r14's name, the suffix of rsi bytes at rdi (none when rsi is 0), then
 * "{" and the labels of the LabelState rdx when it has a label. rax = 1 when a "{" went out, else 0.
 * Locals: the LabelState, the flag, the suffix, its length.
 */
LOCAL_FUNCTION mt_open
    FRAME 32
    mov     %rdx, (%rsp)
    movq    $0, 8(%rsp)
    mov     %rdi, 16(%rsp)
    mov     %rsi, 24(%rsp)
    call    mt_name
    mov     24(%rsp), %rsi
    test    %rsi, %rsi
    jz      1f
    mov     16(%rsp), %rdi
    call    mt_put
1:  mov     (%rsp), %rax
    cmpq    $0, LS_LABEL1(%rax)
    je      9f
    movq    $1, 8(%rsp)
    MT_TEXT mx_lbrace
    mov     (%rsp), %rax
    mov     LS_LABEL1(%rax), %rdi
    mov     LS_I1(%rax), %rsi
    call    mt_label
    mov     (%rsp), %rax
    cmpq    $0, LS_LABEL2(%rax)
    je      9f
    MT_TEXT mx_comma
    mov     (%rsp), %rax
    mov     LS_LABEL2(%rax), %rdi
    mov     LS_I2(%rax), %rsi
    call    mt_label
9:  mov     8(%rsp), %rax
    UNFRAME 32
END_FUNCTION mt_open

/* A sample's end: "}" when rdi is 1, " ", then the decimal rsi and LF. Locals: rsi. */
LOCAL_FUNCTION mt_value
    FRAME 16
    mov     %rsi, (%rsp)
    test    %rdi, %rdi
    jz      1f
    MT_TEXT mx_rbrace
1:  MT_TEXT mx_sp
    mov     (%rsp), %rdi
    call    mt_dec
    MT_TEXT mx_lf
    UNFRAME 16
END_FUNCTION mt_value

/* `{` when rdi is 0, else `,`; then `le="`. Uses rax, rcx, rsi, rdi. */
LOCAL_FUNCTION mt_le
    FRAME 0
    test    %rdi, %rdi
    jnz     1f
    MT_TEXT mx_lbrace
    jmp     2f
1:  MT_TEXT mx_comma
2:  MT_TEXT mx_le
    MT_TEXT mx_eq
    UNFRAME 0
END_FUNCTION mt_le

/*
 * The histogram rdi of the bound set record rsi, with the labels of the LabelState rdx; rcx is the
 * ticks per second for a set of ticks. Locals: the Histogram, the bounds, the LabelState, the tick
 * rate, the bound index, the sum so far.
 */
LOCAL_FUNCTION mt_histogram
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
    call    mt_open
    mov     %rax, %rdi
    call    mt_le
    mov     8(%rsp), %rcx                   # the bound's text
    mov     MetricBounds_first(%rcx), %eax
    add     32(%rsp), %rax
    shl     $4, %rax
    lea     metrics_bound_values(%rip), %rcx
    mov     MetricBound_text(%rcx,%rax), %edi
    mov     MetricBound_text_len(%rcx,%rax), %esi
    call    mt_text
    MT_TEXT mx_quote
    mov     $1, %edi
    mov     40(%rsp), %rsi
    call    mt_value
    incq    32(%rsp)
    jmp     1b
2:  lea     mx_bucket(%rip), %rdi           # +Inf: every value
    mov     $mx_bucket_len, %esi
    mov     16(%rsp), %rdx
    call    mt_open
    mov     %rax, %rdi
    call    mt_le
    MT_TEXT mx_inf
    MT_TEXT mx_quote
    mov     $1, %edi
    mov     (%rsp), %rax
    mov     Histogram_count(%rax), %rsi
    call    mt_value
    lea     mx_sum(%rip), %rdi              # _sum in seconds
    mov     $mx_sum_len, %esi
    mov     16(%rsp), %rdx
    call    mt_open
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
5:  call    mt_seconds
    MT_TEXT mx_lf
    lea     mx_count(%rip), %rdi            # _count
    mov     $mx_count_len, %esi
    mov     16(%rsp), %rdx
    call    mt_open
    mov     %rax, %rdi
    mov     (%rsp), %rax
    mov     Histogram_count(%rax), %rsi
    call    mt_value
    UNFRAME 48
END_FUNCTION mt_histogram

/* The entry r14's name and `{topic="<name>"` of the GossipTopic rdi. Locals: the topic. */
LOCAL_FUNCTION mt_topic
    FRAME 16
    mov     %rdi, (%rsp)
    call    mt_name
    MT_TEXT mx_lbrace
    MT_TEXT mx_topic
    MT_TEXT mx_eq
    mov     (%rsp), %rax
    lea     GossipTopic_name(%rax), %rdi
    mov     GossipTopic_name_length(%rax), %rsi
    call    mt_put
    MT_TEXT mx_quote
    UNFRAME 16
END_FUNCTION mt_topic

/* `,<name>="<value>"`: the name is rsi bytes at rdi, the value rcx bytes at rdx. Locals: the texts. */
LOCAL_FUNCTION mt_pair
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    mov     %rcx, 24(%rsp)
    MT_TEXT mx_comma
    mov     (%rsp), %rdi
    mov     8(%rsp), %rsi
    call    mt_put
    MT_TEXT mx_eq
    mov     16(%rsp), %rdi
    mov     24(%rsp), %rsi
    call    mt_put
    MT_TEXT mx_quote
    UNFRAME 32
END_FUNCTION mt_pair

.macro MT_PAIR name, value
    lea     \name(%rip), %rdi
    mov     $\name\()_len, %esi
    lea     \value(%rip), %rdx
    mov     $\value\()_len, %ecx
    call    mt_pair
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
    call    mt_name
    MT_TEXT mx_sp
    mov     MetricEntry_help(%r14), %edi
    mov     MetricEntry_help_len(%r14), %esi
    call    mt_text
    MT_TEXT mx_lf
    MT_TEXT mx_type
    call    mt_name
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
    call    mt_open
    mov     %rax, %rdi
    mov     (%rbp), %rsi
    call    mt_value
    jmp     80f
41: call    mt_name                         # a root, signed
    MT_TEXT mx_sp
    mov     (%rbp), %rdi
    call    mt_sdec
    MT_TEXT mx_lf
    jmp     80f
42: call    mt_name                         # microseconds as seconds
    MT_TEXT mx_sp
    mov     (%rbp), %rdi
    call    mt_seconds
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
    call    mt_open
    mov     %rax, %rdi
    mov     (L + 64)(%rsp), %rax
    mov     (%rbp,%rax,8), %rsi
    call    mt_value
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
    call    mt_histogram
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
    call    mt_topic
    mov     $1, %edi
    mov     GossipTopic_mesh_peers(%rbp), %rsi
    call    mt_value
    jmp     59f
52: cmp     $METRIC_KIND_GOSSIP_SENT, %eax
    jne     53f
    mov     %rbp, %rdi
    call    mt_topic
    MT_PAIR mx_partial, mx_false
    mov     $1, %edi
    mov     GossipTopic_sent_bytes(%rbp), %rsi
    call    mt_value
    mov     %rbp, %rdi
    call    mt_topic
    MT_PAIR mx_partial, mx_true
    mov     $1, %edi
    mov     GossipTopic_sent_partial_bytes(%rbp), %rsi
    call    mt_value
    jmp     59f
53: mov     %rbp, %rdi                      # mesh peers by partial support
    call    mt_topic
    MT_PAIR mx_supports, mx_false
    mov     $1, %edi
    mov     GossipTopic_mesh_peers(%rbp), %rsi
    sub     GossipTopic_mesh_partial_peers(%rbp), %rsi
    call    mt_value
    mov     %rbp, %rdi
    call    mt_topic
    MT_PAIR mx_supports, mx_true
    mov     $1, %edi
    mov     GossipTopic_mesh_partial_peers(%rbp), %rsi
    call    mt_value
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
