/*
 * Gossip topic strings, ARM64: in the common object. Requirements: docs/reference/networking.md.
 */

/* x0 = the name table entry of GOSSIP_* name x0, or 0 when it names no topic. Uses x9. */
.macro TOPIC_ENTRY reg, name
    sub     \reg, \name, #1
    cmp     \reg, #GOSSIP_NAMES
    b.hs    9f
    ADDRESS x9, gossip_names
    add     \reg, x9, \reg, lsl #4
.endm

/*
 * (topic, out): /eth2/ + hex(fork_digest) + / + name [+ _ + subnet_id] + /ssz_snappy.
 * x2 the name entry, x3 the string length, x4 the write pointer, x5-x8, x10-x14 work.
 */
FUNCTION lantern_gossip_topic
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #GossipTopic_name]
    TOPIC_ENTRY x2, x9
    ldr     x3, [x2, #8]                    /* the name's length; bit 63: a subnet topic */
    lsr     x5, x3, #63
    and     x3, x3, #0xff
    add     x3, x3, #(6 + 8 + 1 + 11)
    ldr     x6, [x0, #GossipTopic_subnet_id]
    mov     x7, #0                          /* digits of the subnet */
    cbz     x5, 2f
    mov     x10, x6
    mov     x11, #10
1:  udiv    x10, x10, x11
    add     x7, x7, #1
    cbnz    x10, 1b
    add     x3, x3, x7
    add     x3, x3, #1
2:  ldr     x10, [x1]                       /* room for the string */
    subs    x10, x10, #24
    b.lo    8f
    cmp     x10, x3
    b.lo    8f
    mov     x10, #24
    stp     x10, x3, [x1, #8]
    add     x4, x1, #24
    mov     w10, #'/'                       /* /eth2/ */
    strb    w10, [x4], #1
    mov     w10, #'e'
    strb    w10, [x4], #1
    mov     w10, #'t'
    strb    w10, [x4], #1
    mov     w10, #'h'
    strb    w10, [x4], #1
    mov     w10, #'2'
    strb    w10, [x4], #1
    mov     w10, #'/'
    strb    w10, [x4], #1
    mov     x10, #0                         /* the digest's 4 bytes, as lowercase hex */
3:  ldrb    w11, [x0, x10]
    lsr     w12, w11, #4
    and     w11, w11, #15
    cmp     w12, #10
    add     w13, w12, #'0'
    add     w12, w12, #('a' - 10)
    csel    w12, w13, w12, lo
    strb    w12, [x4], #1
    cmp     w11, #10
    add     w13, w11, #'0'
    add     w11, w11, #('a' - 10)
    csel    w11, w13, w11, lo
    strb    w11, [x4], #1
    add     x10, x10, #1
    cmp     x10, #4
    b.lo    3b
    mov     w10, #'/'
    strb    w10, [x4], #1
    ldr     x10, [x2]                       /* the name */
    ADDRESS x9, gossip_name_bytes
    add     x10, x9, x10
    ldr     x11, [x2, #8]
    and     x11, x11, #0xff
4:  ldrb    w12, [x10], #1
    strb    w12, [x4], #1
    subs    x11, x11, #1
    b.ne    4b
    cbz     x5, 6f
    mov     w10, #'_'                       /* _ + subnet_id in decimal, written from its last digit */
    strb    w10, [x4], #1
    add     x4, x4, x7
    mov     x12, x4
    mov     x11, #10
5:  udiv    x13, x6, x11
    msub    x14, x13, x11, x6
    add     w14, w14, #'0'
    strb    w14, [x12, #-1]!
    mov     x6, x13
    subs    x7, x7, #1
    b.ne    5b
6:  ADDRESS x9, gossip_suffix               /* /ssz_snappy */
    mov     x11, #11
7:  ldrb    w12, [x9], #1
    strb    w12, [x4], #1
    subs    x11, x11, #1
    b.ne    7b
    mov     x0, #LANTERN_OK
    ret
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    ret
9:  mov     x0, #LANTERN_INVALID_TOPIC
    ret
END_FUNCTION lantern_gossip_topic

/*
 * (string, out): the topic of a string that lantern_gossip_topic writes.
 * x2 the bytes, x3 their count, x4 the digest, x5 the name part, x6 its length, x7 the name,
 * x8 the subnet; x9-x15 work.
 */
FUNCTION lantern_gossip_topic_parse
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #8]
    add     x2, x0, x9
    ldr     x3, [x0, #16]
    cmp     x3, #(6 + 8 + 1 + 1 + 11)
    b.lo    9f
    ADDRESS x9, gossip_prefix               /* /eth2/ */
    mov     x10, #0
1:  ldrb    w11, [x2, x10]
    ldrb    w12, [x9, x10]
    cmp     w11, w12
    b.ne    9f
    add     x10, x10, #1
    cmp     x10, #6
    b.lo    1b
    mov     x4, #0                          /* 8 lowercase hex digits */
    mov     x10, #6
2:  ldrb    w11, [x2, x10]
    sub     w12, w11, #'0'
    cmp     w12, #10
    b.lo    3f
    sub     w12, w11, #'a'
    cmp     w12, #6
    b.hs    9f
    add     w12, w12, #10
3:  lsl     x4, x4, #4
    orr     x4, x4, x12
    add     x10, x10, #1
    cmp     x10, #14
    b.lo    2b
    ldrb    w11, [x2, #14]
    cmp     w11, #'/'
    b.ne    9f
    ADDRESS x9, gossip_suffix               /* /ssz_snappy at the end */
    sub     x10, x3, #11
    add     x10, x2, x10
    mov     x11, #0
4:  ldrb    w12, [x10, x11]
    ldrb    w13, [x9, x11]
    cmp     w12, w13
    b.ne    9f
    add     x11, x11, #1
    cmp     x11, #11
    b.lo    4b
    add     x5, x2, #15                     /* the name part: from 15 to the suffix */
    sub     x6, x3, #(15 + 11)
    mov     x7, #1                          /* each name in turn */
5:  sub     x9, x7, #1
    ADDRESS x10, gossip_names
    add     x9, x10, x9, lsl #4
    ldr     x10, [x9]
    ADDRESS x11, gossip_name_bytes
    add     x10, x11, x10                   /* the name's bytes */
    ldr     x11, [x9, #8]
    lsr     x12, x11, #63                   /* a subnet topic */
    and     x11, x11, #0xff
    cmp     x6, x11                         /* the name part starts with the name */
    b.lo    7f
    mov     x13, #0
6:  ldrb    w14, [x5, x13]
    ldrb    w15, [x10, x13]
    cmp     w14, w15
    b.ne    7f
    add     x13, x13, #1
    cmp     x13, x11
    b.lo    6b
    mov     x8, #0
    cmp     x6, x11                         /* exactly the name: a topic without a subnet */
    b.ne    10f
    cbnz    x12, 7f
    b       12f
10: cbz     x12, 7f                         /* name + _ + canonical decimal */
    add     x13, x11, #1
    cmp     x6, x13
    b.ls    7f
    ldrb    w14, [x5, x11]
    cmp     w14, #'_'
    b.ne    7f
    sub     x15, x6, x13                    /* digits */
    ldrb    w14, [x5, x13]
    cmp     w14, #'0'
    b.ne    11f
    cmp     x15, #1                         /* a leading zero */
    b.ne    7f
11: ldrb    w14, [x5, x13]
    sub     w14, w14, #'0'
    cmp     w14, #10
    b.hs    7f
    mov     x10, #10
    umulh   x11, x8, x10
    cbnz    x11, 7f
    mul     x8, x8, x10
    adds    x8, x8, x14
    b.cs    7f
    add     x13, x13, #1
    cmp     x13, x6
    b.lo    11b
12: rev     w4, w4                          /* the digest's bytes in order */
    str     x4, [x1, #GossipTopic_fork_digest]
    stp     x7, x8, [x1, #GossipTopic_name]
    mov     x0, #LANTERN_OK
    ret
7:  add     x7, x7, #1
    cmp     x7, #GOSSIP_NAMES
    b.ls    5b
9:  mov     x0, #LANTERN_INVALID_TOPIC
    ret
END_FUNCTION lantern_gossip_topic_parse
GOSSIP_TOPIC_DATA
