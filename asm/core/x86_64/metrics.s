/*
 * Metrics, x86-64: in the common object. Requirements: docs/reference/metrics.md.
 *
 * The writers keep the cursor in r12 and the end of the room in r13; r15 becomes 1 when the room
 * runs out, and nothing is written from then on. rbx holds metrics_texts.
 */

    RODATA
.include "metrics_table.inc"

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

/*
 * A histogram's samples: the entry r14, its Histogram at rdi and its bounds table at rsi. Locals:
 * the Histogram, the bounds, the bound index, the sum so far.
 */
LOCAL_FUNCTION mt_histogram
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    movq    $0, 16(%rsp)
    movq    $0, 24(%rsp)
1:  mov     16(%rsp), %rax                  # each bound: the values at or below it
    mov     8(%rsp), %rcx
    cmp     (%rcx), %rax
    jae     2f
    mov     (%rsp), %rdx
    mov     Histogram_buckets(%rdx,%rax,8), %rdx
    add     %rdx, 24(%rsp)
    call    mt_name
    MT_TEXT mx_bucket
    mov     16(%rsp), %rax
    shl     $4, %rax
    add     8(%rsp), %rax
    mov     16(%rax), %edi                  # its text: offset, length
    mov     20(%rax), %esi
    call    mt_text
    MT_TEXT mx_le_end
    mov     24(%rsp), %rdi
    call    mt_dec
    MT_TEXT mx_lf
    incq    16(%rsp)
    jmp     1b
2:  call    mt_name                         # +Inf: every value
    MT_TEXT mx_bucket
    MT_TEXT mx_inf
    MT_TEXT mx_le_end
    mov     (%rsp), %rax
    mov     Histogram_count(%rax), %rdi
    call    mt_dec
    MT_TEXT mx_lf
    call    mt_name                         # _sum in seconds, _count
    MT_TEXT mx_sum
    mov     (%rsp), %rax
    mov     Histogram_sum_us(%rax), %rdi
    call    mt_seconds
    MT_TEXT mx_lf
    call    mt_name
    MT_TEXT mx_count
    mov     (%rsp), %rax
    mov     Histogram_count(%rax), %rdi
    call    mt_dec
    MT_TEXT mx_lf
    UNFRAME 32
END_FUNCTION mt_histogram

/* The topic label of the GossipTopic rdi: `{topic="<name>`. Locals: the entry. */
LOCAL_FUNCTION mt_topic
    FRAME 16
    mov     %rdi, (%rsp)
    call    mt_name
    MT_TEXT mx_topic
    mov     (%rsp), %rax
    lea     GossipTopic_name(%rax), %rdi
    mov     GossipTopic_name_length(%rax), %rsi
    call    mt_put
    UNFRAME 16
END_FUNCTION mt_topic

/*
 * lantern_metrics_text(categories, state, node, app, process, gossip, out) -> status
 * The Prometheus text of the metrics of the categories. rbx metrics_texts, r12 the cursor, r13 the
 * end of the room, r14 a table entry, r15 1 when the room ran out, rbp the entry's source. Locals:
 * L the sources by METRIC_SRC_* (state, node, app, process, gossip), L+40 out, L+48 a gossip
 * entry, L+56 the gossip entries left, L+64 a value.
 */
FUNCTION lantern_metrics_text
    ENTER 80
    mov     %rsi, L(%rsp)
    mov     %rdx, (L + 8)(%rsp)
    mov     %rcx, (L + 16)(%rsp)
    mov     %r8, (L + 24)(%rsp)
    mov     %r9, (L + 32)(%rsp)
    mov     (80 + 96)(%rsp), %rax           # the seventh argument
    mov     %rax, (L + 40)(%rsp)
    mov     (%rdi), %rdi
    lea     24(%rax), %r12
    mov     (%rax), %r13
    add     %rax, %r13
    xor     %r15d, %r15d
    lea     metrics_texts(%rip), %rbx
    test    $METRICS_BEACON, %rdi
    jz      90f
    lea     metrics_table(%rip), %r14
1:  lea     metrics_table_end(%rip), %rax
    cmp     %rax, %r14
    jae     90f
    mov     MetricEntry_source(%r14), %eax  # its source
    mov     L(%rsp,%rax,8), %rbp
    movzwl  MetricEntry_cond(%r14), %eax    # its condition
    cmp     $METRIC_COND_NONE, %eax
    je      10f
    mov     L(%rsp), %rcx                   # MetricsState
    cmp     $METRIC_COND_STATE, %eax
    jne     2f
    cmpq    $0, MetricsState_present(%rcx)
    je      80f
    jmp     10f
2:  cmp     $METRIC_COND_ELECTRA, %eax
    jne     3f
    cmpq    $0, MetricsState_present(%rcx)
    je      80f
    cmpq    $0, MetricsState_electra(%rcx)
    je      80f
    jmp     10f
3:  mov     (L + 8)(%rsp), %rcx             # MetricsNode
    cmp     $METRIC_COND_FULU, %eax
    jne     4f
    cmpq    $0, MetricsNode_fulu(%rcx)
    je      80f
    jmp     10f
4:  cmp     $METRIC_COND_STATE_ROOT, %eax
    jne     5f
    mov     L(%rsp), %rcx                   # MetricsState
    cmpq    $0, MetricsState_present(%rcx)
    je      80f
    cmpq    $0, MetricsState_state_root_present(%rcx)
    je      80f
    jmp     10f
5:  mov     (L + 24)(%rsp), %rcx            # MetricsProcess: METRIC_COND_MAX_FDS
    cmpq    $0, MetricsProcess_max_fds(%rcx)
    je      80f
10: movzwl  MetricEntry_kind(%r14), %eax    # a gossipsub metric with no sample goes out
    cmp     $METRIC_KIND_GOSSIP_MAIN, %eax
    jb      20f
    mov     %eax, %edx
    PART    %rcx, %rsi, %rbp, MetricsGossip_topics
11: test    %rsi, %rsi
    jz      80f
    cmp     $METRIC_KIND_GOSSIP_MAIN, %edx
    jne     20f
    cmpq    $0, GossipTopic_subnet(%rcx)
    je      20f
    add     $GossipTopic__mem, %rcx
    dec     %rsi
    jmp     11b
20: MT_TEXT mx_help                         # # HELP <name> <help>, # TYPE <name> <type>
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
    je      22f
    ja      23f
    MT_TEXT mx_gauge
    jmp     24f
22: MT_TEXT mx_counter
    jmp     24f
23: MT_TEXT mx_histogram
24: mov     MetricEntry_offset(%r14), %eax  # its samples
    add     %rax, %rbp                      # the value, in its source
    movzwl  MetricEntry_kind(%r14), %eax
    cmp     $METRIC_KIND_U64, %eax
    jne     30f
    call    mt_name
    MT_TEXT mx_sp
    mov     (%rbp), %rdi
    call    mt_dec
    MT_TEXT mx_lf
    jmp     80f
30: cmp     $METRIC_KIND_ROOT, %eax
    jne     31f
    call    mt_name
    MT_TEXT mx_sp
    mov     (%rbp), %rdi
    call    mt_sdec
    MT_TEXT mx_lf
    jmp     80f
31: cmp     $METRIC_KIND_SECONDS, %eax
    jne     32f
    call    mt_name
    MT_TEXT mx_sp
    mov     (%rbp), %rdi
    call    mt_seconds
    MT_TEXT mx_lf
    jmp     80f
32: cmp     $METRIC_KIND_STATUS, %eax
    jne     33f
    call    mt_name
    MT_TEXT mx_st_pending
    mov     (%rbp), %rdi
    call    mt_dec
    MT_TEXT mx_lf
    call    mt_name
    MT_TEXT mx_st_active
    mov     8(%rbp), %rdi
    call    mt_dec
    MT_TEXT mx_lf
    call    mt_name
    MT_TEXT mx_st_exited
    mov     16(%rbp), %rdi
    call    mt_dec
    MT_TEXT mx_lf
    call    mt_name
    MT_TEXT mx_st_withdrawable
    mov     24(%rbp), %rdi
    call    mt_dec
    MT_TEXT mx_lf
    jmp     80f
33: cmp     $METRIC_KIND_HIST_DEFAULT, %eax
    jne     34f
    lea     mb_default(%rip), %rsi
    jmp     36f
34: cmp     $METRIC_KIND_HIST_KZG, %eax
    jne     35f
    lea     mb_kzg(%rip), %rsi
    jmp     36f
35: cmp     $METRIC_KIND_HIST_DELAY, %eax
    jne     40f
    lea     mb_delay(%rip), %rsi
36: mov     %rbp, %rdi
    call    mt_histogram
    jmp     80f
40: mov     %eax, (L + 64)(%rsp)            # gossipsub: each topic
    mov     MetricEntry_offset(%r14), %eax
    sub     %rax, %rbp                      # the MetricsGossip again
    PART    %rcx, %rsi, %rbp, MetricsGossip_topics
    mov     %rcx, (L + 48)(%rsp)
    mov     %rsi, (L + 56)(%rsp)
41: cmpq    $0, (L + 56)(%rsp)
    je      80f
    mov     (L + 48)(%rsp), %rbp
    mov     (L + 64)(%rsp), %eax
    cmp     $METRIC_KIND_GOSSIP_MAIN, %eax
    jne     42f
    cmpq    $0, GossipTopic_subnet(%rbp)    # main topics only
    jne     49f
    mov     %rbp, %rdi
    call    mt_topic
    MT_TEXT mx_topic_end
    mov     GossipTopic_mesh_peers(%rbp), %rdi
    call    mt_dec
    MT_TEXT mx_lf
    jmp     49f
42: cmp     $METRIC_KIND_GOSSIP_SENT, %eax
    jne     43f
    mov     %rbp, %rdi
    call    mt_topic
    MT_TEXT mx_partial_f
    mov     GossipTopic_sent_bytes(%rbp), %rdi
    call    mt_dec
    MT_TEXT mx_lf
    mov     %rbp, %rdi
    call    mt_topic
    MT_TEXT mx_partial_t
    mov     GossipTopic_sent_partial_bytes(%rbp), %rdi
    call    mt_dec
    MT_TEXT mx_lf
    jmp     49f
43: mov     %rbp, %rdi                      # mesh peers by partial support
    call    mt_topic
    MT_TEXT mx_supports_f
    mov     GossipTopic_mesh_peers(%rbp), %rdi
    sub     GossipTopic_mesh_partial_peers(%rbp), %rdi
    call    mt_dec
    MT_TEXT mx_lf
    mov     %rbp, %rdi
    call    mt_topic
    MT_TEXT mx_supports_t
    mov     GossipTopic_mesh_partial_peers(%rbp), %rdi
    call    mt_dec
    MT_TEXT mx_lf
49: addq    $GossipTopic__mem, (L + 48)(%rsp)
    decq    (L + 56)(%rsp)
    jmp     41b
80: add     $MetricEntry__mem, %r14
    jmp     1b
90: test    %r15, %r15                      # the text's length, or no room
    jnz     91f
    mov     (L + 40)(%rsp), %rax
    movq    $24, 8(%rax)
    lea     24(%rax), %rcx
    sub     %rcx, %r12
    mov     %r12, 16(%rax)
    xor     %eax, %eax
    LEAVE 80
91: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 80
END_FUNCTION lantern_metrics_text
