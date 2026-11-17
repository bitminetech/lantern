/*
 * Gossip topic strings, RISC-V: in the common object. Requirements: docs/reference/networking.md.
 */

/* t3 = the lowercase hex digit of the value 0 to 15 in t3. Uses t4. */
.macro HEX_DIGIT
    li      t4, 10
    bltu    t3, t4, 91f
    addi    t3, t3, 'a' - 10 - '0'
91: addi    t3, t3, '0'
.endm

/*
 * (topic, out): /eth2/ + hex(fork_digest) + / + name [+ _ + subnet_id] + /ssz_snappy.
 * a2 the name entry, a3 the string length, a4 the write pointer, a5 a subnet topic,
 * a6 the subnet, a7 its digits; t0-t5 work.
 */
FUNCTION lantern_gossip_topic
    ld      t0, GossipTopic_name(a0)
    addi    t0, t0, -1
    li      t1, GOSSIP_NAMES
    bgeu    t0, t1, 9f
    slli    t0, t0, 4
    ADDRESS a2, gossip_names
    add     a2, a2, t0
    ld      a3, 8(a2)                       # the name's length; bit 63: a subnet topic
    srli    a5, a3, 63
    andi    a3, a3, 0xff
    addi    a3, a3, 6 + 8 + 1 + 11
    ld      a6, GossipTopic_subnet_id(a0)
    li      a7, 0                           # digits of the subnet
    beqz    a5, 2f
    mv      t0, a6
    li      t1, 10
1:  divu    t0, t0, t1
    addi    a7, a7, 1
    bnez    t0, 1b
    add     a3, a3, a7
    addi    a3, a3, 1
2:  ld      t0, 0(a1)                       # room for the string
    li      t1, 24
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    bltu    t0, a3, 8f
    sd      t1, 8(a1)
    sd      a3, 16(a1)
    addi    a4, a1, 24
    ADDRESS t0, gossip_prefix               # /eth2/
    li      t1, 6
3:  lbu     t2, 0(t0)
    sb      t2, 0(a4)
    addi    t0, t0, 1
    addi    a4, a4, 1
    addi    t1, t1, -1
    bnez    t1, 3b
    li      t0, 0                           # the digest's 4 bytes, as lowercase hex
4:  add     t1, a0, t0
    lbu     t2, 0(t1)
    srli    t3, t2, 4
    HEX_DIGIT
    sb      t3, 0(a4)
    andi    t3, t2, 15
    HEX_DIGIT
    sb      t3, 1(a4)
    addi    a4, a4, 2
    addi    t0, t0, 1
    li      t1, 4
    bltu    t0, t1, 4b
    li      t0, '/'
    sb      t0, 0(a4)
    addi    a4, a4, 1
    ld      t0, 0(a2)                       # the name
    ADDRESS t1, gossip_name_bytes
    add     t0, t0, t1
    ld      t1, 8(a2)
    andi    t1, t1, 0xff
5:  lbu     t2, 0(t0)
    sb      t2, 0(a4)
    addi    t0, t0, 1
    addi    a4, a4, 1
    addi    t1, t1, -1
    bnez    t1, 5b
    beqz    a5, 7f
    li      t0, '_'                         # _ + subnet_id in decimal, written from its last digit
    sb      t0, 0(a4)
    addi    a4, a4, 1
    add     a4, a4, a7
    mv      t2, a4
    li      t1, 10
6:  remu    t3, a6, t1
    divu    a6, a6, t1
    addi    t3, t3, '0'
    addi    t2, t2, -1
    sb      t3, 0(t2)
    addi    a7, a7, -1
    bnez    a7, 6b
7:  ADDRESS t0, gossip_suffix               # /ssz_snappy
    li      t1, 11
10: lbu     t2, 0(t0)
    sb      t2, 0(a4)
    addi    t0, t0, 1
    addi    a4, a4, 1
    addi    t1, t1, -1
    bnez    t1, 10b
    li      a0, LANTERN_OK
    ret
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    ret
9:  li      a0, LANTERN_INVALID_TOPIC
    ret
END_FUNCTION lantern_gossip_topic

/*
 * (string, out): the topic of a string that lantern_gossip_topic writes.
 * a2 the bytes, a3 their count, a4 the digest, a5 the name part, a6 its length, a7 the name,
 * t6 the subnet; t0-t5 work.
 */
FUNCTION lantern_gossip_topic_parse
    ld      t0, 8(a0)
    add     a2, a0, t0
    ld      a3, 16(a0)
    li      t0, 6 + 8 + 1 + 1 + 11
    bltu    a3, t0, 9f
    ADDRESS t0, gossip_prefix               # /eth2/
    li      t1, 0
1:  add     t2, a2, t1
    lbu     t2, 0(t2)
    add     t3, t0, t1
    lbu     t3, 0(t3)
    bne     t2, t3, 9f
    addi    t1, t1, 1
    li      t3, 6
    bltu    t1, t3, 1b
    li      a4, 0                           # 8 lowercase hex digits
    li      t1, 6
2:  add     t2, a2, t1
    lbu     t2, 0(t2)
    addi    t3, t2, -'0'
    li      t4, 10
    bltu    t3, t4, 3f
    addi    t3, t2, -'a'
    li      t4, 6
    bgeu    t3, t4, 9f
    addi    t3, t3, 10
3:  slli    a4, a4, 4
    or      a4, a4, t3
    addi    t1, t1, 1
    li      t3, 14
    bltu    t1, t3, 2b
    lbu     t2, 14(a2)
    li      t3, '/'
    bne     t2, t3, 9f
    ADDRESS t0, gossip_suffix               # /ssz_snappy at the end
    add     t1, a2, a3
    addi    t1, t1, -11
    li      t2, 0
4:  add     t3, t1, t2
    lbu     t3, 0(t3)
    add     t4, t0, t2
    lbu     t4, 0(t4)
    bne     t3, t4, 9f
    addi    t2, t2, 1
    li      t3, 11
    bltu    t2, t3, 4b
    addi    a5, a2, 15                      # the name part: from 15 to the suffix
    addi    a6, a3, -(15 + 11)
    li      a7, 1                           # each name in turn
5:  addi    t0, a7, -1
    slli    t0, t0, 4
    ADDRESS t1, gossip_names
    add     t0, t0, t1
    ld      t1, 0(t0)
    ADDRESS t2, gossip_name_bytes
    add     t1, t1, t2                      # the name's bytes
    ld      t2, 8(t0)
    srli    t5, t2, 63                      # a subnet topic
    andi    t2, t2, 0xff                    # the name's length
    bltu    a6, t2, 7f                      # the name part starts with the name
    li      t0, 0
6:  add     t3, a5, t0
    lbu     t3, 0(t3)
    add     t4, t1, t0
    lbu     t4, 0(t4)
    bne     t3, t4, 7f
    addi    t0, t0, 1
    bltu    t0, t2, 6b
    li      t6, 0                           # the subnet
    bne     a6, t2, 10f                     # exactly the name: a topic without a subnet
    bnez    t5, 7f
    j       12f
10: beqz    t5, 7f                          # name + _ + canonical decimal
    addi    t0, t2, 1
    bgeu    t0, a6, 7f
    add     t3, a5, t2
    lbu     t3, 0(t3)
    li      t4, '_'
    bne     t3, t4, 7f
    add     t3, a5, t0
    lbu     t3, 0(t3)
    li      t4, '0'
    bne     t3, t4, 11f
    addi    t3, t0, 1                       # a leading zero
    bne     t3, a6, 7f
11: add     t3, a5, t0
    lbu     t3, 0(t3)
    addi    t3, t3, -'0'
    li      t4, 10
    bgeu    t3, t4, 7f
    mulhu   t1, t6, t4
    bnez    t1, 7f
    mul     t6, t6, t4
    add     t4, t6, t3
    bltu    t4, t6, 7f
    mv      t6, t4
    addi    t0, t0, 1
    bltu    t0, a6, 11b
12: li      t0, 0                           # the digest's bytes in order: the first hex pair first
    srli    t1, a4, 24
    andi    t1, t1, 0xff
    or      t0, t0, t1
    srli    t1, a4, 16
    andi    t1, t1, 0xff
    slli    t1, t1, 8
    or      t0, t0, t1
    srli    t1, a4, 8
    andi    t1, t1, 0xff
    slli    t1, t1, 16
    or      t0, t0, t1
    andi    t1, a4, 0xff
    slli    t1, t1, 24
    or      t0, t0, t1
    sd      t0, GossipTopic_fork_digest(a1)
    sd      a7, GossipTopic_name(a1)
    sd      t6, GossipTopic_subnet_id(a1)
    li      a0, LANTERN_OK
    ret
7:  addi    a7, a7, 1
    li      t0, GOSSIP_NAMES
    bleu    a7, t0, 5b
9:  li      a0, LANTERN_INVALID_TOPIC
    ret
END_FUNCTION lantern_gossip_topic_parse

GOSSIP_TOPIC_DATA
